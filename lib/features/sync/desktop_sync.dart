import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/sync/change_set.dart';
import '../../core/sync/net/pairing.dart';
import '../../core/sync/net/sessions.dart';
import '../../core/sync/net/sync_client.dart';
import '../../core/sync/sync_engine.dart';
import 'sync_providers.dart';

/// The sync client of the Windows app: talks to the phone it paired with.
final syncClientProvider = FutureProvider<SyncClient>((ref) async {
  final engine = await ref.watch(syncEngineProvider.future);
  final blobs = await ref.watch(syncBlobsProvider.future);
  return SyncClient(
    engine: engine,
    blobSource: blobs,
    blobSink: blobs,
    store: DbHostCredentialStore(ref.watch(databaseProvider)),
    deviceName: 'CardKeep on ${_pcName()}',
    platform: 'windows',
  );
});

String _pcName() {
  try {
    return Platform.localHostname;
  } catch (_) {
    return 'this PC';
  }
}

/// Minutes between automatic syncs while the app is open; 0 = only when asked.
const autoSyncChoices = [0, 5, 10, 30];

class DesktopSyncState {
  /// The phone this PC is paired with, or null.
  final HostCredentials? host;
  final SyncPeer? peer;
  final bool loaded;
  final bool busy;
  final SyncProgress? progress;
  final SyncRoundResult? last;
  final String? error;
  final String? notice;
  final int autoMinutes;

  const DesktopSyncState({
    this.host,
    this.peer,
    this.loaded = false,
    this.busy = false,
    this.progress,
    this.last,
    this.error,
    this.notice,
    this.autoMinutes = 10,
  });

  bool get paired => host != null;

  DesktopSyncState copyWith({
    HostCredentials? host,
    bool clearHost = false,
    SyncPeer? peer,
    bool clearPeer = false,
    bool? loaded,
    bool? busy,
    SyncProgress? progress,
    bool clearProgress = false,
    SyncRoundResult? last,
    String? error,
    bool clearError = false,
    String? notice,
    bool clearNotice = false,
    int? autoMinutes,
  }) => DesktopSyncState(
    host: clearHost ? null : (host ?? this.host),
    peer: clearPeer ? null : (peer ?? this.peer),
    loaded: loaded ?? this.loaded,
    busy: busy ?? this.busy,
    progress: clearProgress ? null : (progress ?? this.progress),
    last: last ?? this.last,
    error: clearError ? null : (error ?? this.error),
    notice: clearNotice ? null : (notice ?? this.notice),
    autoMinutes: autoMinutes ?? this.autoMinutes,
  );
}

/// A line a person can act on, for whatever went wrong talking to the phone.
String syncErrorText(Object e) {
  if (e is SyncException) return e.message;
  if (e is SyncFormatException) return e.message;
  if (e is TimeoutException || e is SocketException || e is HandshakeException || e is TlsException) {
    return 'Could not reach the phone. Open Sync to desktop on the phone, check both are on the same Wi-Fi (not a guest network), then try again.';
  }
  return 'Something went wrong talking to the phone: $e';
}

/// Pairing, "Sync now", the automatic timer and unpairing for the Windows app.
class DesktopSyncController extends Notifier<DesktopSyncState> {
  Timer? _timer;

  @override
  DesktopSyncState build() {
    ref.onDispose(() => _timer?.cancel());
    Future.microtask(load);
    return const DesktopSyncState();
  }

  Future<void> load() async {
    final client = await ref.read(syncClientProvider.future);
    final host = await client.store.load();
    final minutes = await ref.read(settingsRepoProvider).syncAutoMinutes();
    final peer = host == null ? null : await client.engine.peer(host.hostId);
    state = state.copyWith(
      loaded: true,
      host: host,
      clearHost: host == null,
      peer: peer,
      clearPeer: peer == null,
      autoMinutes: minutes,
    );
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = null;
    if (!state.paired || state.autoMinutes <= 0) return;
    _timer = Timer.periodic(Duration(minutes: state.autoMinutes), (_) {
      if (!state.busy) unawaited(syncNow(quiet: true));
    });
  }

  Future<void> setAutoMinutes(int minutes) async {
    await ref.read(settingsRepoProvider).setSyncAutoMinutes(minutes);
    state = state.copyWith(autoMinutes: minutes);
    _arm();
  }

  /// Pairs with the phone whose code text was pasted, then does a first sync.
  Future<void> pair(String codeText) async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearError: true, clearNotice: true);
    try {
      final payload = PairingPayload.parse(codeText);
      final client = await ref.read(syncClientProvider.future);
      final creds = await client.pair(payload);
      final peer = await client.engine.peer(creds.hostId);
      state = state.copyWith(host: creds, peer: peer, notice: 'Paired with ${creds.hostName}.', busy: false);
      _arm();
      await syncNow(keepNotice: true);
    } catch (e) {
      state = state.copyWith(busy: false, error: syncErrorText(e));
    }
  }

  /// One full sync round. [quiet] (the timer) keeps errors short and leaves notices alone;
  /// [keepNotice] leaves the "Paired with…" line up through the first sync.
  Future<void> syncNow({bool quiet = false, bool keepNotice = false}) async {
    if (state.busy || !state.paired) return;
    state = state.copyWith(busy: true, clearError: true, clearNotice: !quiet && !keepNotice);
    try {
      final client = await ref.read(syncClientProvider.future);
      final result = await client.sync(onProgress: (p) => state = state.copyWith(progress: p));
      final peer = await client.engine.peer(state.host!.hostId);
      state = state.copyWith(busy: false, clearProgress: true, last: result, peer: peer);
      ref.read(databaseProvider).markTablesUpdated([ref.read(databaseProvider).syncConflicts]);
    } catch (e) {
      state = state.copyWith(
        busy: false,
        clearProgress: true,
        error: quiet ? 'Auto sync could not reach the phone.' : syncErrorText(e),
      );
    }
  }

  /// Forgets the phone here and tells it to forget this PC.
  Future<void> unpair() async {
    final client = await ref.read(syncClientProvider.future);
    await client.unpair();
    _timer?.cancel();
    state = state.copyWith(
      clearHost: true,
      clearPeer: true,
      clearProgress: true,
      notice: 'Unpaired. This PC no longer syncs with the phone.',
    );
  }
}

final desktopSyncProvider = NotifierProvider<DesktopSyncController, DesktopSyncState>(DesktopSyncController.new);
