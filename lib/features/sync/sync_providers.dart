import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../core/sync/image_blobs.dart';
import '../../core/sync/net/device_certificate.dart';
import '../../core/sync/net/pairing.dart';
import '../../core/sync/net/sessions.dart';
import '../../core/sync/net/sync_server.dart';
import '../../core/sync/sync_engine.dart';

/// The images the sync can send and receive: this phone's card images and logos.
final syncBlobsProvider = FutureProvider<ImageBlobStore>(
  (ref) async => ImageBlobStore(await ref.watch(imageStoreProvider.future)),
);

/// The sync engine on this phone's database; people it changes get their search
/// entry rebuilt.
final syncEngineProvider = FutureProvider<SyncEngine>((ref) async {
  final contacts = ref.watch(contactsRepoProvider);
  return SyncEngine(
    ref.watch(databaseProvider),
    blobs: await ref.watch(syncBlobsProvider.future),
    reindexPeople: (ids) async {
      for (final id in ids) {
        await contacts.reindex(id);
      }
    },
  );
});

/// Fields both devices changed that still wait for a choice (the drawer badge).
final openConflictsProvider = StreamProvider<int>((ref) {
  final db = ref.watch(databaseProvider);
  return db
      .customSelect('SELECT COUNT(*) AS n FROM sync_conflicts WHERE resolved_at IS NULL', readsFrom: {db.syncConflicts})
      .watch()
      .map((rows) => rows.single.read<int>('n'));
});

/// Test hooks for [SyncHostController].
class SyncHostOverrides {
  final InternetAddress? bindTo;
  final String? host;
  final Future<Directory> Function() certificateDir;
  const SyncHostOverrides({this.bindTo, this.host, required this.certificateDir});
}

/// Where the host is in getting ready.
enum SyncHostPhase { starting, ready, noNetwork, failed }

class SyncHostState {
  final SyncHostPhase phase;

  /// The pairing code on show, and when it stops working.
  final PairingPayload? payload;
  final DateTime? codeExpiresAt;
  final List<SyncPeer> peers;

  /// What the PC is doing right now ("" when idle), and a one-off line such as
  /// "Paired with Joe's PC".
  final String activity;
  final String? notice;
  final String? error;

  const SyncHostState({
    this.phase = SyncHostPhase.starting,
    this.payload,
    this.codeExpiresAt,
    this.peers = const [],
    this.activity = '',
    this.notice,
    this.error,
  });

  SyncHostState copyWith({
    SyncHostPhase? phase,
    PairingPayload? payload,
    bool clearPayload = false,
    DateTime? codeExpiresAt,
    List<SyncPeer>? peers,
    String? activity,
    String? notice,
    bool clearNotice = false,
    String? error,
  }) => SyncHostState(
    phase: phase ?? this.phase,
    payload: clearPayload ? null : (payload ?? this.payload),
    codeExpiresAt: clearPayload ? null : (codeExpiresAt ?? this.codeExpiresAt),
    peers: peers ?? this.peers,
    activity: activity ?? this.activity,
    notice: clearNotice ? null : (notice ?? this.notice),
    error: error,
  );
}

/// Runs the sync host for as long as the Sync screen is open: starts the
/// HTTPS server on the Wi-Fi address, shows pairing codes, and stops everything
/// when the screen goes away.
class SyncHostController extends Notifier<SyncHostState> {
  SyncServer? _server;
  StreamSubscription<SyncEvent>? _events;
  Timer? _quiet;
  bool _gone = false;

  /// Tests: bind on loopback, put 127.0.0.1 in the code, keep the certificate in a temp folder.
  static SyncHostOverrides? overrides;

  @override
  SyncHostState build() {
    ref.onDispose(() {
      _gone = true;
      _quiet?.cancel();
      _events?.cancel();
      _server?.dispose();
    });
    Future.microtask(start);
    return const SyncHostState();
  }

  Future<void> start() async {
    if (_server != null) return;
    state = state.copyWith(phase: SyncHostPhase.starting, error: null);
    try {
      final engine = await ref.read(syncEngineProvider.future);
      final blobs = await ref.read(syncBlobsProvider.future);
      final docs = await (overrides?.certificateDir ?? getApplicationDocumentsDirectory)();
      final cert = await CertificateStore(docs).loadOrCreate();
      final server = SyncServer(
        engine: engine,
        certificate: cert,
        blobSource: blobs,
        blobSink: blobs,
        deviceName: 'CardKeep on this phone',
      );
      await server.start(bindTo: overrides?.bindTo);
      if (_gone) {
        await server.dispose();
        return;
      }
      _server = server;
      _events = server.events.listen(_onEvent);
      state = state.copyWith(phase: SyncHostPhase.ready, peers: await engine.peers());
      if (state.peers.isEmpty) await newCode();
    } on NoNetworkException {
      if (!_gone) state = state.copyWith(phase: SyncHostPhase.noNetwork);
    } catch (e) {
      if (!_gone) state = state.copyWith(phase: SyncHostPhase.failed, error: '$e');
    }
  }

  /// A fresh pairing code (the old one stops working).
  Future<void> newCode() async {
    final s = _server;
    if (s == null) return;
    final payload = await s.newPairing(host: overrides?.host);
    if (_gone) return;
    state = state.copyWith(payload: payload, codeExpiresAt: s.tokens.expiresAt, clearNotice: true);
  }

  Future<void> unpair(String peerId) async {
    final engine = await ref.read(syncEngineProvider.future);
    await engine.unpair(peerId);
    await SessionStore(ref.read(databaseProvider)).remove(peerId);
    state = state.copyWith(peers: await engine.peers(), notice: 'Unpaired. The PC no longer has access.');
    if (state.peers.isEmpty) await newCode();
  }

  Future<void> refreshPeers() async {
    final engine = await ref.read(syncEngineProvider.future);
    if (_gone) return;
    state = state.copyWith(peers: await engine.peers());
  }

  void _onEvent(SyncEvent e) {
    if (_gone) return;
    switch (e.type) {
      case 'paired':
        state = state.copyWith(clearPayload: true, notice: 'Paired with ${e.peerName ?? 'your PC'}.');
        unawaited(refreshPeers());
      case 'unpaired':
        unawaited(refreshPeers());
      case 'pulling':
        state = state.copyWith(activity: 'The PC is fetching changes from this phone…');
      case 'receiving':
        state = state.copyWith(activity: 'The PC is sending changes to this phone…');
      case 'blob':
        state = state.copyWith(activity: 'Moving card photos…');
    }
    if (e.type == 'pulling' || e.type == 'receiving' || e.type == 'blob') {
      _quiet?.cancel();
      _quiet = Timer(const Duration(seconds: 3), () {
        if (_gone) return;
        state = state.copyWith(activity: '', notice: 'Synced.');
        unawaited(refreshPeers());
        ref.read(databaseProvider).markTablesUpdated([ref.read(databaseProvider).syncConflicts]);
      });
    }
  }
}

final syncHostProvider = NotifierProvider.autoDispose<SyncHostController, SyncHostState>(SyncHostController.new);
