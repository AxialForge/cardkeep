import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Variable;

import '../blob_transfer.dart';
import '../change_set.dart';
import '../sync_engine.dart';
import 'pairing.dart';
import 'sessions.dart';
import 'sync_server.dart' show KindAwareBlobSink;
import 'wire.dart';

/// Why a sync did not happen, in words that fit on a screen. [code] is for tests
/// and for choosing the help text.
class SyncException implements Exception {
  /// unreachable, cert_mismatch, bad_token, unauthorized, not_paired,
  /// not_on_your_network, too_many_attempts, newer_version, interrupted, server
  final String code;
  final String message;
  const SyncException(this.code, this.message);
  @override
  String toString() => message;
}

/// How far a sync has got, for a progress bar.
class SyncProgress {
  /// connecting, receiving, sending, images, finishing
  final String phase;
  final int done;
  final int total;
  final String message;
  const SyncProgress(this.phase, this.done, this.total, this.message);
}

/// What one sync round did.
class SyncRoundResult {
  /// Rows taken from the host, rows sent to it.
  final int received, sent;

  /// Images fetched and images uploaded.
  final int imagesDown, imagesUp;

  /// Fields both devices changed (waiting for a choice), found in this round.
  final int conflicts;
  final Duration took;
  const SyncRoundResult({
    this.received = 0,
    this.sent = 0,
    this.imagesDown = 0,
    this.imagesUp = 0,
    this.conflicts = 0,
    this.took = Duration.zero,
  });
}

/// The other end of the sync (the PC; in tests, a second phone): pairs with a
/// host from its QR, then runs rounds: take the host's changes, send ours, move
/// the images either way, and tell the host what arrived. Talks only to the
/// address in the QR, and only to a server showing the certificate whose sha256
/// the QR carried.
class SyncClient {
  final SyncEngine engine;
  final BlobSource blobSource;
  final BlobSink blobSink;
  final HostCredentialStore store;
  final String deviceName;
  final String platform;
  final DateTime Function() clock;

  /// Rows per page and bytes per image chunk.
  final int pageRows;
  final int chunkBytes;
  final Duration timeout;

  /// For tests: stop after this many image chunks, as if the link dropped.
  int? debugMaxBlobChunks;

  SyncClient({
    required this.engine,
    required this.blobSource,
    required this.blobSink,
    required this.store,
    required this.deviceName,
    this.platform = 'windows',
    DateTime Function()? clock,
    this.pageRows = 1000,
    this.chunkBytes = 256 * 1024,
    this.timeout = const Duration(seconds: 12),
    this.debugMaxBlobChunks,
  }) : clock = clock ?? DateTime.now;

  int _nowSeconds() => clock().millisecondsSinceEpoch ~/ 1000;

  // ----------------------------------------------------------------- pairing

  /// Pairs with the host in [payload]. Uses the one-time token, trusts only the
  /// certificate the QR names, and keeps the session the host returns.
  Future<HostCredentials> pair(PairingPayload payload) async {
    final myId = await engine.myDeviceId();
    final client = _http(payload.certSha256);
    try {
      final t0 = clock().millisecondsSinceEpoch;
      final reply = await _json(
        client,
        'POST',
        payload.host,
        payload.port,
        '/pair',
        body: {
          'token': payload.token,
          'device_id': myId,
          'device_name': deviceName,
          'platform': platform,
          'time': _nowSeconds(),
        },
      );
      final t1 = clock().millisecondsSinceEpoch;
      final hostId = reply['device_id'] as String;
      final hostTime = reply['time'] as int;
      // The host's clock minus ours at the middle of the exchange.
      final offset = hostTime - (((t0 + t1) ~/ 2) ~/ 1000);
      final creds = HostCredentials(
        hostId: hostId,
        hostName: reply['device_name'] as String? ?? payload.deviceName,
        host: payload.host,
        port: payload.port,
        fingerprint: payload.certSha256,
        session: reply['session'] as String,
      );
      await engine.registerPeer(
        hostId,
        name: creds.hostName,
        platform: 'android',
        certFingerprint: payload.certSha256,
        clockOffsetSeconds: offset,
      );
      await store.save(creds);
      return creds;
    } finally {
      client.close(force: true);
    }
  }

  /// Tells the host this device is leaving and forgets it. Works even when the
  /// host cannot be reached (the pairing is forgotten here anyway).
  Future<void> unpair() async {
    final creds = await store.load();
    if (creds == null) return;
    final client = _http(creds.fingerprint);
    try {
      await _json(client, 'POST', creds.host, creds.port, '/unpair', session: creds.session, body: const {});
    } on SyncException {
      // the host is away: leave anyway
    } finally {
      client.close(force: true);
      await engine.unpair(creds.hostId);
      await store.clear();
    }
  }

  /// True when the host answers and shows the pinned certificate.
  Future<bool> reachable() async {
    final creds = await store.load();
    if (creds == null) return false;
    final client = _http(creds.fingerprint);
    try {
      final r = await _json(client, 'GET', creds.host, creds.port, '/hello');
      return r['app'] == syncAppName;
    } on SyncException {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  // -------------------------------------------------------------------- sync

  /// One full round. Safe to repeat or to run again after it was interrupted:
  /// the watermarks move only when the last page of a direction is applied, and
  /// images resume where they stopped.
  Future<SyncRoundResult> sync({void Function(SyncProgress)? onProgress}) async {
    final started = clock();
    final creds = await store.load();
    if (creds == null) throw const SyncException('not_paired', 'This device is not paired with a phone yet.');
    final client = _http(creds.fingerprint);
    void report(String phase, int done, int total, String message) =>
        onProgress?.call(SyncProgress(phase, done, total, message));
    try {
      report('connecting', 0, 0, 'Connecting to ${creds.hostName}…');
      final offset = (await engine.peer(creds.hostId))?.clockOffsetSeconds;
      var received = 0, sent = 0, conflicts = 0;
      // Images still to move, kept between rounds so a dropped link resumes.
      final pending = await _loadPending();
      final needDown = pending.down;
      final needUp = pending.up;

      // 1. Take the host's changes.
      String? cursor;
      do {
        final json = await _json(
          client,
          'GET',
          creds.host,
          creds.port,
          '/changes',
          session: creds.session,
          query: {'cursor': ?cursor, 'limit': '$pageRows'},
        );
        final cs = ChangeSet.fromJson(json);
        final kinds = blobKindsOf(cs);
        final result = await engine.apply(cs, clockOffset: offset);
        received += cs.rowCount;
        conflicts += result.conflicts.length;
        for (final h in result.blobsNeeded) {
          needDown[h] = kinds[h] ?? blobKindCard;
        }
        await _savePending(pending);
        await _json(
          client,
          'POST',
          creds.host,
          creds.port,
          '/ack',
          session: creds.session,
          body: {
            'cursor': cursor ?? '',
            'conflicts': [for (final c in result.conflicts) conflictToJson(c)],
          },
        );
        report('receiving', received, 0, 'Received $received changes');
        cursor = cs.next;
      } while (cursor != null);

      // 2. Send ours.
      cursor = null;
      do {
        final cs = await engine.buildChanges(peerId: creds.hostId, cursor: cursor, limit: pageRows);
        final kinds = blobKindsOf(cs);
        final reply = PushReply.fromJson(
          await _json(client, 'POST', creds.host, creds.port, '/changes', session: creds.session, body: cs.toJson()),
        );
        await engine.acknowledge(creds.hostId, cs, peerConflicts: reply.conflicts);
        sent += cs.rowCount;
        conflicts += reply.conflicts.length;
        for (final h in reply.blobsNeeded) {
          needUp[h] = kinds[h] ?? blobKindCard;
        }
        await _savePending(pending);
        report('sending', sent, 0, 'Sent $sent changes');
        cursor = cs.next;
      } while (cursor != null);

      // 3. Images, both ways.
      var down = 0, up = 0;
      final total = needDown.length + needUp.length;
      var doneImages = 0;
      // An image leaves the pending list once it is here (or the other device
      // does not have it); an interrupted one stays and resumes next round.
      for (final e in needDown.entries.toList()) {
        if (await _download(client, creds, e.key, e.value)) down++;
        needDown.remove(e.key);
        await _savePending(pending);
        report('images', ++doneImages, total, 'Images $doneImages of $total');
      }
      for (final e in needUp.entries.toList()) {
        if (await _upload(client, creds, e.key, e.value)) up++;
        needUp.remove(e.key);
        await _savePending(pending);
        report('images', ++doneImages, total, 'Images $doneImages of $total');
      }
      report('finishing', 0, 0, 'Done');
      return SyncRoundResult(
        received: received,
        sent: sent,
        imagesDown: down,
        imagesUp: up,
        conflicts: conflicts,
        took: clock().difference(started),
      );
    } finally {
      client.close(force: true);
    }
  }

  // ------------------------------------------------------------------ images

  static const _pendingKey = 'sync.pending_blobs';

  Future<_PendingBlobs> _loadPending() async {
    final r = await engine.db
        .customSelect('SELECT value FROM app_settings WHERE key = ?', variables: [Variable.withString(_pendingKey)])
        .getSingleOrNull();
    final p = _PendingBlobs();
    if (r == null) return p;
    try {
      final j = (jsonDecode(r.read<String>('value')) as Map).cast<String, Object?>();
      p.down.addAll((j['down'] as Map? ?? const {}).cast<String, String>());
      p.up.addAll((j['up'] as Map? ?? const {}).cast<String, String>());
    } catch (_) {
      // damaged: start the list again
    }
    return p;
  }

  Future<void> _savePending(_PendingBlobs p) =>
      engine.db.customStatement('INSERT OR REPLACE INTO app_settings (key, value) VALUES (?, ?)', [
        _pendingKey,
        jsonEncode({'down': p.down, 'up': p.up}),
      ]);

  Future<bool> _download(HttpClient client, HostCredentials c, String sha, String kind) async {
    if (await blobSink.has(sha)) return true;
    final sink = blobSink;
    if (sink is KindAwareBlobSink) (sink as KindAwareBlobSink).expect(sha, kind);
    final head = await _raw(client, 'HEAD', c.host, c.port, '/blob/$sha', session: c.session, query: {'kind': kind});
    if (head.status != 200) return false;
    final total = int.parse(head.headers['x-ck-size'] ?? '0');
    var offset = await sink.received(sha);
    var chunks = 0;
    while (offset < total) {
      if (debugMaxBlobChunks != null && chunks >= debugMaxBlobChunks!) {
        throw const SyncException('interrupted', 'The connection dropped while moving images.');
      }
      final r = await _raw(
        client,
        'GET',
        c.host,
        c.port,
        '/blob/$sha',
        session: c.session,
        query: {'kind': kind},
        headers: {HttpHeaders.rangeHeader: 'bytes=$offset-${offset + chunkBytes - 1}'},
      );
      if (r.status != 206 && r.status != 200) throw const SyncException('server', 'The phone could not send an image.');
      if (r.bytes.isEmpty) return false;
      await sink.write(sha, offset, r.bytes);
      offset += r.bytes.length;
      chunks++;
    }
    return sink.commit(sha);
  }

  Future<bool> _upload(HttpClient client, HostCredentials c, String sha, String kind) async {
    final total = await blobSource.size(sha);
    if (total == null || total == 0) return false;
    final head = await _raw(client, 'HEAD', c.host, c.port, '/blob/$sha', session: c.session, query: {'kind': kind});
    if (head.status == 200) return true;
    var offset = int.tryParse(head.headers['x-ck-received'] ?? '') ?? 0;
    var chunks = 0;
    while (offset < total) {
      if (debugMaxBlobChunks != null && chunks >= debugMaxBlobChunks!) {
        throw const SyncException('interrupted', 'The connection dropped while moving images.');
      }
      final bytes = await blobSource.read(sha, offset, chunkBytes);
      if (bytes.isEmpty) return false;
      final r = await _raw(
        client,
        'PUT',
        c.host,
        c.port,
        '/blob/$sha',
        session: c.session,
        query: {'kind': kind, 'offset': '$offset', 'total': '$total'},
        body: bytes,
      );
      if (r.status == 409) {
        final now = ((jsonDecode(utf8.decode(r.bytes)) as Map)['received'] as int?) ?? 0;
        offset = now;
        continue;
      }
      if (r.status == 422) return false;
      if (r.status != 200) throw const SyncException('server', 'The phone could not take an image.');
      offset += bytes.length;
      chunks++;
    }
    return true;
  }

  // -------------------------------------------------------------------- http

  /// A client that trusts exactly one certificate: the one whose sha256 is
  /// [fingerprint]. A self-signed certificate fails the normal checks, so the
  /// callback decides; it says yes only for the pinned one.
  HttpClient _http(String fingerprint) {
    final c = HttpClient(context: SecurityContext(withTrustedRoots: false));
    c.badCertificateCallback = (cert, host, port) => sha256.convert(cert.der).toString() == fingerprint;
    c.connectionTimeout = timeout;
    c.idleTimeout = const Duration(seconds: 5);
    return c;
  }

  Future<Map<String, Object?>> _json(
    HttpClient client,
    String method,
    String host,
    int port,
    String path, {
    String? session,
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    final r = await _raw(
      client,
      method,
      host,
      port,
      path,
      session: session,
      query: query,
      body: body == null ? null : Uint8List.fromList(utf8.encode(jsonEncode(body))),
      headers: body == null ? null : {HttpHeaders.contentTypeHeader: 'application/json'},
    );
    Object? decoded;
    try {
      decoded = r.bytes.isEmpty ? <String, Object?>{} : jsonDecode(utf8.decode(r.bytes));
    } on FormatException {
      throw const SyncException('server', 'The phone sent something CardKeep could not read.');
    }
    final map = decoded is Map ? decoded.cast<String, Object?>() : <String, Object?>{};
    if (r.status >= 200 && r.status < 300) return map;
    throw _errorFor(r.status, map);
  }

  SyncException _errorFor(int status, Map<String, Object?> body) {
    final code = body['error'] as String? ?? 'server';
    final message = body['message'] as String?;
    return switch (code) {
      'bad_token' => SyncException(
        'bad_token',
        message ?? 'That pairing code has expired or was already used. Show a new one on the phone.',
      ),
      'unauthorized' => const SyncException('unauthorized', 'The phone no longer knows this device. Pair them again.'),
      'not_on_your_network' => const SyncException(
        'not_on_your_network',
        'The phone only talks to devices on the same Wi-Fi.',
      ),
      'too_many_attempts' ||
      'too_many_requests' => SyncException('too_many_attempts', message ?? 'Too many tries. Wait a minute.'),
      _ => SyncException('server', message ?? 'The phone could not do that (error $status).'),
    };
  }

  Future<_Raw> _raw(
    HttpClient client,
    String method,
    String host,
    int port,
    String path, {
    String? session,
    Map<String, String>? query,
    Uint8List? body,
    Map<String, String>? headers,
  }) async {
    try {
      final uri = Uri(scheme: 'https', host: host, port: port, path: path, queryParameters: query);
      final req = await client.openUrl(method, uri).timeout(timeout);
      if (session != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $session');
      headers?.forEach(req.headers.set);
      if (body != null) {
        req.contentLength = body.length;
        req.add(body);
      }
      final res = await req.close().timeout(timeout);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in res.timeout(timeout)) {
        bytes.add(chunk);
      }
      final out = <String, String>{};
      res.headers.forEach((name, values) => out[name.toLowerCase()] = values.join(','));
      return _Raw(res.statusCode, bytes.takeBytes(), out);
    } on HandshakeException {
      throw const SyncException(
        'cert_mismatch',
        'This is not the phone you paired with (its certificate is different). Pair again from the phone.',
      );
    } on TlsException {
      throw const SyncException(
        'cert_mismatch',
        'This is not the phone you paired with (its certificate is different). Pair again from the phone.',
      );
    } on SocketException {
      throw const SyncException(
        'unreachable',
        'Could not reach the phone. Check that both are on the same Wi-Fi and the Sync screen is open on the phone.',
      );
    } on TimeoutException {
      throw const SyncException(
        'unreachable',
        'The phone did not answer. Check the Wi-Fi, and that a firewall is not blocking CardKeep.',
      );
    } on HttpException {
      throw const SyncException('unreachable', 'The connection to the phone dropped.');
    }
  }
}

class _Raw {
  final int status;
  final Uint8List bytes;
  final Map<String, String> headers;
  const _Raw(this.status, this.bytes, this.headers);
}

class _PendingBlobs {
  final Map<String, String> down = {};
  final Map<String, String> up = {};
}
