import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../blob_transfer.dart';
import '../change_set.dart';
import '../sync_engine.dart';
import 'device_certificate.dart';
import 'lan.dart';
import 'pairing.dart';
import 'sessions.dart';
import 'wire.dart';

/// An image store that wants to know whether a hash is a card or a logo before
/// its bytes arrive (they live in different folders). Optional.
abstract interface class KindAwareBlobSink {
  void expect(String sha256, String kind);
}

/// Something that happened on the host, for the Sync screen.
class SyncEvent {
  /// paired, pulling (the peer is fetching changes), receiving (the peer sent
  /// changes), blob, unpaired
  final String type;
  final String? peerId;
  final String? peerName;
  final int rows;
  const SyncEvent(this.type, {this.peerId, this.peerName, this.rows = 0});
}

/// Thrown by start() when the device is on no home network.
class NoNetworkException implements Exception {
  const NoNetworkException();
  @override
  String toString() => 'This phone is not on a Wi-Fi network.';
}

class _HttpError implements Exception {
  final int status;
  final String code;
  final String message;
  const _HttpError(this.status, this.code, this.message);
}

/// The sync host (the phone): an HTTPS server that exists only while the Sync
/// screen is open, answers only devices on the local network, and serves the
/// [SyncEngine]. Pure Dart, so the Windows app can host too (S16.8, later).
///
/// Endpoints (all JSON unless noted; everything but /hello and /pair needs
/// `Authorization: Bearer <session>`):
///  * GET  /hello                      who is this (no secrets)
///  * POST /pair                       {token, device_id, device_name, platform, time}
///  * GET  /changes?cursor=&limit=     the next page of changes for the caller
///  * POST /ack                        {cursor, conflicts}: the caller applied that page
///  * POST /changes                    a ChangeSet pushed by the caller
///  * POST /unpair                     the caller leaves
///  * HEAD/GET/PUT /blob/{sha256}      images, in resumable chunks
class SyncServer {
  final SyncEngine engine;
  final DeviceCertificate certificate;
  final BlobSource blobSource;
  final BlobSink blobSink;
  final String deviceName;
  final String platform;
  final DateTime Function() clock;

  /// Who may talk to this server. Default: devices on a private network.
  final bool Function(InternetAddress) addressAllowed;

  final PairingTokens tokens;
  final SessionStore sessions;

  /// Largest JSON body, and largest blob chunk, in bytes.
  final int maxJsonBytes;
  final int maxChunkBytes;

  /// Requests per minute from one address, and bad pairing attempts per minute.
  final int requestsPerMinute;
  final int pairFailuresPerMinute;

  /// Two devices only (phone and one PC): pairing a new device unpairs the others.
  final bool replaceExistingPeers;

  HttpServer? _server;
  final _events = StreamController<SyncEvent>.broadcast();
  final Map<String, Map<String, ChangeSet>> _sent = {};
  final Map<String, List<DateTime>> _hits = {};
  final Map<String, List<DateTime>> _pairFailures = {};
  Future<void> _lock = Future.value();

  SyncServer({
    required this.engine,
    required this.certificate,
    required this.blobSource,
    required this.blobSink,
    required this.deviceName,
    this.platform = 'android',
    DateTime Function()? clock,
    bool Function(InternetAddress)? addressAllowed,
    PairingTokens? tokens,
    SessionStore? sessions,
    this.maxJsonBytes = 8 * 1024 * 1024,
    this.maxChunkBytes = 1024 * 1024,
    this.requestsPerMinute = 3000,
    this.pairFailuresPerMinute = 5,
    this.replaceExistingPeers = true,
  }) : clock = clock ?? DateTime.now,
       addressAllowed = addressAllowed ?? isPrivateAddress,
       tokens = tokens ?? PairingTokens(clock: clock),
       sessions = sessions ?? SessionStore(engine.db);

  Stream<SyncEvent> get events => _events.stream;
  bool get isRunning => _server != null;
  int get port => _server?.port ?? 0;

  /// Starts listening on this device's home-network address (or [bindTo]) and
  /// [port] (0 = any free port). Throws [NoNetworkException] with no Wi-Fi.
  Future<void> start({InternetAddress? bindTo, int port = 0}) async {
    if (_server != null) return;
    final address = bindTo ?? await bestLanAddress();
    if (address == null) throw const NoNetworkException();
    final server = await HttpServer.bindSecure(address, port, certificate.serverContext());
    _server = server;
    server.listen(_handle, onError: (_) {}, cancelOnError: false);
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    tokens.clear();
    _sent.clear();
    await s?.close(force: true);
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
  }

  /// A fresh pairing code for the QR: the address a PC can reach, a one-time
  /// token good for two minutes, and this device's certificate fingerprint.
  Future<PairingPayload> newPairing({String? host}) async {
    final s = _server;
    if (s == null) throw StateError('The sync server is not running.');
    return PairingPayload(
      host: host ?? s.address.address,
      port: s.port,
      token: tokens.issue(),
      certSha256: certificate.fingerprint,
      deviceName: deviceName,
    );
  }

  // ------------------------------------------------------------------ routing

  Future<void> _handle(HttpRequest req) async {
    try {
      final remote = req.connectionInfo?.remoteAddress;
      if (remote == null || !addressAllowed(remote)) {
        throw const _HttpError(403, 'not_on_your_network', 'Only devices on your own network may sync.');
      }
      if (!_allowRate(_hits, remote.address, requestsPerMinute)) {
        throw const _HttpError(429, 'too_many_requests', 'Slow down.');
      }
      final path = req.uri.path;
      final method = req.method;
      if (path == '/hello' && method == 'GET') return _hello(req);
      if (path == '/pair' && method == 'POST') return await _pair(req, remote.address);
      final peerId = await _authenticate(req);
      if (path == '/changes' && method == 'GET') return await _getChanges(req, peerId);
      if (path == '/changes' && method == 'POST') return await _postChanges(req, peerId);
      if (path == '/ack' && method == 'POST') return await _ack(req, peerId);
      if (path == '/unpair' && method == 'POST') return await _unpair(req, peerId);
      if (path.startsWith('/blob/')) return await _blob(req, peerId, path.substring(6));
      throw const _HttpError(404, 'not_found', 'No such page.');
    } on _HttpError catch (e) {
      await _reply(req, e.status, {'error': e.code, 'message': e.message});
    } on SyncFormatException catch (e) {
      await _reply(req, 400, {'error': 'bad_request', 'message': e.message});
    } catch (_) {
      await _reply(req, 500, {'error': 'server_error', 'message': 'Something went wrong on the phone.'});
    }
  }

  bool _allowRate(Map<String, List<DateTime>> book, String key, int limit) {
    final now = clock();
    final list = (book[key] ??= []);
    list.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    if (list.length >= limit) return false;
    list.add(now);
    return true;
  }

  Future<String> _authenticate(HttpRequest req) async {
    final header = req.headers.value(HttpHeaders.authorizationHeader);
    final token = header != null && header.startsWith('Bearer ') ? header.substring(7).trim() : null;
    final peerId = await sessions.verify(token);
    if (peerId == null || await engine.peer(peerId) == null) {
      throw const _HttpError(401, 'unauthorized', 'This device is not paired.');
    }
    return peerId;
  }

  Future<T> _locked<T>(Future<T> Function() job) {
    final done = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        done.complete(await job());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  // ---------------------------------------------------------------- endpoints

  void _hello(HttpRequest req) {
    unawaited(_reply(req, 200, {'app': syncAppName, 'protocol': syncProtocolVersion, 'name': deviceName}));
  }

  Future<void> _pair(HttpRequest req, String remote) async {
    final failures = (_pairFailures[remote] ?? [])
        .where((t) => clock().difference(t) <= const Duration(minutes: 1))
        .length;
    if (failures >= pairFailuresPerMinute) {
      throw const _HttpError(429, 'too_many_attempts', 'Too many wrong pairing attempts. Wait a minute.');
    }
    final body = _object(decodeJsonBody(await _readBody(req, 64 * 1024)));
    final token = body['token'];
    final id = body['device_id'];
    final name = body['device_name'];
    final time = body['time'];
    if (token is! String || id is! String || name is! String || time is! int || id.isEmpty || id.contains('.')) {
      throw const _HttpError(400, 'bad_request', 'The pairing request is incomplete.');
    }
    if (!tokens.consume(token)) {
      (_pairFailures[remote] ??= []).add(clock());
      throw const _HttpError(401, 'bad_token', 'That pairing code has expired or was already used.');
    }
    final myId = await engine.myDeviceId();
    if (id == myId) throw const _HttpError(400, 'same_device', 'That is this phone.');
    final now = clock().millisecondsSinceEpoch ~/ 1000;
    final session = await _locked(() async {
      if (replaceExistingPeers) {
        for (final p in await engine.peers()) {
          if (p.id == id) continue;
          await engine.unpair(p.id);
          await sessions.remove(p.id);
          _sent.remove(p.id);
          _events.add(SyncEvent('unpaired', peerId: p.id, peerName: p.name));
        }
      }
      await engine.registerPeer(
        id,
        name: name,
        platform: body['platform'] as String? ?? 'windows',
        certFingerprint: certificate.fingerprint,
        // The peer's clock minus ours, seen at this moment.
        clockOffsetSeconds: time - now,
      );
      return sessions.create(id);
    });
    _events.add(SyncEvent('paired', peerId: id, peerName: name));
    await _reply(req, 200, {
      'device_id': myId,
      'device_name': deviceName,
      'session': session,
      'time': now,
      'protocol': syncProtocolVersion,
    });
  }

  Future<void> _getChanges(HttpRequest req, String peerId) async {
    final cursor = req.uri.queryParameters['cursor'];
    final limit = int.tryParse(req.uri.queryParameters['limit'] ?? '');
    final cs = await _locked(() async {
      if (cursor == null || cursor.isEmpty) _sent.remove(peerId);
      final built = await engine.buildChanges(
        peerId: peerId,
        cursor: cursor == null || cursor.isEmpty ? null : cursor,
        limit: limit?.clamp(1, 20000),
      );
      (_sent[peerId] ??= {})[cursor ?? ''] = built;
      return built;
    });
    _events.add(SyncEvent('pulling', peerId: peerId, rows: cs.rowCount));
    await _reply(req, 200, cs.toJson());
  }

  Future<void> _ack(HttpRequest req, String peerId) async {
    final body = _object(decodeJsonBody(await _readBody(req, maxJsonBytes)));
    final cursor = (body['cursor'] as String?) ?? '';
    final sent = _sent[peerId]?[cursor];
    if (sent == null) throw const _HttpError(409, 'no_such_page', 'That page was not sent in this round.');
    final conflicts = [
      for (final c in (body['conflicts'] as List? ?? const [])) conflictFromJson((c as Map).cast<String, Object?>()),
    ];
    await _locked(() => engine.acknowledge(peerId, sent, peerConflicts: conflicts));
    _sent[peerId]?.remove(cursor);
    await _reply(req, 200, {'ok': true});
  }

  Future<void> _postChanges(HttpRequest req, String peerId) async {
    final body = _object(decodeJsonBody(await _readBody(req, maxJsonBytes)));
    final cs = ChangeSet.fromJson(body);
    if (cs.deviceId != peerId) throw const _HttpError(403, 'wrong_device', 'These changes are from another device.');
    final result = await _locked(() => engine.apply(cs));
    _events.add(SyncEvent('receiving', peerId: peerId, rows: cs.rowCount));
    await _reply(req, 200, applyResultToJson(result));
  }

  Future<void> _unpair(HttpRequest req, String peerId) async {
    await req.drain<void>();
    final peer = await engine.peer(peerId);
    await _locked(() async {
      await engine.unpair(peerId);
      await sessions.remove(peerId);
      _sent.remove(peerId);
    });
    _events.add(SyncEvent('unpaired', peerId: peerId, peerName: peer?.name));
    await _reply(req, 200, {'ok': true});
  }

  static final _sha = RegExp(r'^[0-9a-f]{64}$');

  Future<void> _blob(HttpRequest req, String peerId, String sha) async {
    if (!_sha.hasMatch(sha)) throw const _HttpError(400, 'bad_hash', 'Not an image hash.');
    final kind = req.uri.queryParameters['kind'];
    final sink = blobSink;
    if (kind != null && sink is KindAwareBlobSink) (sink as KindAwareBlobSink).expect(sha, kind);
    switch (req.method) {
      case 'HEAD':
        final size = await blobSource.size(sha);
        req.response.statusCode = size != null ? 200 : 404;
        if (size != null) {
          req.response.headers.set('x-ck-size', '$size');
        } else {
          req.response.headers.set('x-ck-received', '${await blobSink.received(sha)}');
        }
        await req.response.close();
      case 'GET':
        final size = await blobSource.size(sha);
        if (size == null) throw const _HttpError(404, 'no_such_blob', 'This phone does not have that image.');
        final range = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(req.headers.value(HttpHeaders.rangeHeader) ?? '');
        final start = range == null ? 0 : int.parse(range.group(1)!);
        if (start >= size && size > 0) throw const _HttpError(416, 'bad_range', 'Past the end of the image.');
        var end = range == null || range.group(2)!.isEmpty ? size - 1 : int.parse(range.group(2)!);
        if (end >= size) end = size - 1;
        if (end - start + 1 > maxChunkBytes) end = start + maxChunkBytes - 1;
        final bytes = size == 0 ? Uint8List(0) : await blobSource.read(sha, start, end - start + 1);
        req.response.statusCode = 206;
        req.response.headers
          ..set(HttpHeaders.contentRangeHeader, 'bytes $start-${start + bytes.length - 1}/$size')
          ..set(HttpHeaders.contentTypeHeader, 'application/octet-stream')
          ..set('x-ck-size', '$size');
        req.response.contentLength = bytes.length;
        req.response.add(bytes);
        await req.response.close();
        _events.add(SyncEvent('blob', peerId: peerId));
      case 'PUT':
        final offset = int.tryParse(req.uri.queryParameters['offset'] ?? '');
        final total = int.tryParse(req.uri.queryParameters['total'] ?? '');
        if (offset == null || total == null || offset < 0 || total < 1) {
          throw const _HttpError(400, 'bad_request', 'offset and total are needed.');
        }
        final bytes = Uint8List.fromList(await _readBody(req, maxChunkBytes));
        if (await blobSink.has(sha)) return await _reply(req, 200, {'done': true});
        final have = await blobSink.received(sha);
        if (offset != have) {
          return await _reply(req, 409, {'error': 'wrong_offset', 'received': have});
        }
        await _locked(() => blobSink.write(sha, offset, bytes));
        if (offset + bytes.length >= total) {
          final ok = await _locked(() => blobSink.commit(sha));
          if (!ok) return await _reply(req, 422, {'error': 'hash_mismatch', 'message': 'The image arrived damaged.'});
          _events.add(SyncEvent('blob', peerId: peerId));
          return await _reply(req, 200, {'done': true});
        }
        await _reply(req, 200, {'done': false, 'received': offset + bytes.length});
      default:
        throw const _HttpError(405, 'method_not_allowed', 'Not allowed.');
    }
  }

  // ------------------------------------------------------------------ helpers

  Map<String, Object?> _object(Object? json) {
    if (json is! Map) throw const _HttpError(400, 'bad_request', 'Expected a JSON object.');
    return json.cast<String, Object?>();
  }

  Future<List<int>> _readBody(HttpRequest req, int max) async {
    if (req.contentLength > max) throw const _HttpError(413, 'too_large', 'That message is too large.');
    final b = BytesBuilder(copy: false);
    await for (final chunk in req) {
      b.add(chunk);
      if (b.length > max) throw const _HttpError(413, 'too_large', 'That message is too large.');
    }
    return b.takeBytes();
  }

  Future<void> _reply(HttpRequest req, int status, Map<String, Object?> json) async {
    try {
      final bytes = utf8.encode(jsonEncode(json));
      req.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..contentLength = bytes.length
        ..add(bytes);
      await req.response.close();
    } catch (_) {
      // the other end hung up
    }
  }
}
