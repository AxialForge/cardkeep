import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:card_organizer/core/sync/change_set.dart';
import 'package:card_organizer/core/sync/net/device_certificate.dart';
import 'package:card_organizer/core/sync/sync_engine.dart';
import 'package:card_organizer/core/sync/net/lan.dart';
import 'package:card_organizer/core/sync/net/pairing.dart';
import 'package:card_organizer/core/sync/net/sessions.dart';
import 'package:card_organizer/core/sync/net/sync_client.dart';
import 'package:card_organizer/core/sync/net/sync_server.dart';
import 'package:card_organizer/core/sync/net/wire.dart';
import 'package:card_organizer/core/sync/blob_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../sync_helpers.dart';

late DeviceCertificate cert;

DateTime Function() clockOf(Node n) =>
    () => DateTime.fromMillisecondsSinceEpoch(n.t * 1000);

/// A phone (host) and a PC (client) in one process, talking over loopback.
class Rig {
  final World world = World();
  late final Node phone = Node('phone', world);
  late final Node pc = Node('pc', world);
  final phoneBlobs = MemoryBlobStore();
  final pcBlobs = MemoryBlobStore();
  late SyncServer server;
  late SyncClient client;
  late SyncEngine phoneEngine;
  late SyncEngine pcEngine;

  static Future<Rig> create({
    int pcSkew = 0,
    bool Function(InternetAddress)? allowed,
    int maxJson = 8 * 1024 * 1024,
    int requestsPerMinute = 3000,
    int pageRows = 1000,
    int chunk = 64 * 1024,
  }) async {
    final r = Rig._();
    await r.phone.init();
    await r.pc.init();
    r.phoneEngine = SyncEngine(r.phone.db, blobs: r.phoneBlobs, clock: clockOf(r.phone));
    r.pcEngine = SyncEngine(r.pc.db, blobs: r.pcBlobs, clock: clockOf(r.pc));
    r.server = SyncServer(
      engine: r.phoneEngine,
      certificate: cert,
      blobSource: r.phoneBlobs,
      blobSink: r.phoneBlobs,
      deviceName: 'Test phone',
      clock: clockOf(r.phone),
      addressAllowed: allowed,
      maxJsonBytes: maxJson,
      requestsPerMinute: requestsPerMinute,
    );
    await r.server.start(bindTo: InternetAddress.loopbackIPv4);
    r.client = SyncClient(
      engine: r.pcEngine,
      blobSource: r.pcBlobs,
      blobSink: r.pcBlobs,
      store: DbHostCredentialStore(r.pc.db),
      deviceName: 'Test PC',
      clock: clockOf(r.pc),
      pageRows: pageRows,
      chunkBytes: chunk,
    );
    return r;
  }

  Rig._();

  Future<PairingPayload> payload() => server.newPairing(host: '127.0.0.1');

  Future<HostCredentials> pairNow() async => client.pair(await payload());

  Future<void> close() async {
    await server.dispose();
    await phone.close();
    await pc.close();
  }
}

Future<(int, Map<String, Object?>)> rawPost(Rig r, String path, List<int> body, {String? session}) async {
  final c = HttpClient()..badCertificateCallback = (_, _, _) => true;
  try {
    final req = await c.postUrl(Uri.parse('https://127.0.0.1:${r.server.port}$path'));
    if (session != null) req.headers.set('authorization', 'Bearer $session');
    req.contentLength = body.length;
    req.add(body);
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return (res.statusCode, text.isEmpty ? <String, Object?>{} : (jsonDecode(text) as Map).cast<String, Object?>());
  } finally {
    c.close(force: true);
  }
}

void main() {
  setUpAll(() async => cert = await DeviceCertificate.generate());

  group('addresses and the pairing code', () {
    test('only home-network addresses are private', () {
      bool p(String a) => isPrivateAddress(InternetAddress(a));
      expect(p('192.168.1.20'), isTrue);
      expect(p('10.0.0.5'), isTrue);
      expect(p('172.16.4.4'), isTrue);
      expect(p('172.31.255.1'), isTrue);
      expect(p('127.0.0.1'), isTrue);
      expect(p('169.254.3.3'), isTrue);
      expect(p('fd12:3456::1'), isTrue);
      expect(p('::1'), isTrue);
      expect(p('172.32.0.1'), isFalse);
      expect(p('172.15.0.1'), isFalse);
      expect(p('8.8.8.8'), isFalse);
      expect(p('100.64.0.1'), isFalse, reason: 'carrier-grade NAT is not your network');
      expect(p('2001:4860:4860::8888'), isFalse);
      expect(p('::ffff:192.168.1.5'), isTrue);
      expect(p('::ffff:8.8.8.8'), isFalse);
    });

    test('the QR text round-trips and rejects other text', () {
      final a = PairingPayload(
        host: '192.168.1.20',
        port: 49152,
        token: 'abc',
        certSha256: 'a' * 64,
        deviceName: 'Joe\'s phone',
      );
      final b = PairingPayload.parse(a.toQrText());
      expect([b.host, b.port, b.token, b.certSha256, b.deviceName, b.version], [
        a.host,
        a.port,
        a.token,
        a.certSha256,
        a.deviceName,
        a.version,
      ]);
      expect(() => PairingPayload.parse('https://example.com'), throwsA(isA<SyncFormatException>()));
      expect(() => PairingPayload.parse('cardkeep-sync:!!!'), throwsA(isA<SyncFormatException>()));
      final newer = 'cardkeep-sync:${base64Url.encode(utf8.encode(jsonEncode({...a.toJson(), 'v': 99})))}';
      expect(() => PairingPayload.parse(newer), throwsA(isA<SyncFormatException>()));
    });

    test('a token works once and for two minutes', () {
      var now = DateTime(2026, 1, 1, 12);
      final t = PairingTokens(clock: () => now);
      final a = t.issue();
      expect(t.consume(a), isTrue);
      expect(t.consume(a), isFalse, reason: 'single use');
      final b = t.issue();
      now = now.add(const Duration(minutes: 2, seconds: 1));
      expect(t.consume(b), isFalse, reason: 'expired');
      final c = t.issue();
      final d = t.issue();
      expect(t.consume(c), isFalse, reason: 'a newer code replaces the older one');
      expect(t.consume(d), isTrue);
    });
  });

  group('pairing', () {
    test('pairs, stores the session, and measures the clock offset', () async {
      final r = await Rig.create();
      addTearDown(r.close);
      r.pc.world.advance(0);
      final creds = await r.pairNow();
      expect(creds.hostId, r.phone.id);
      expect(creds.session, startsWith('${r.pc.id}.'));
      expect((await r.phone.engine.peers()).single.id, r.pc.id);
      expect((await r.pc.engine.peers()).single.id, r.phone.id);
      expect((await r.phone.engine.peer(r.pc.id))!.clockOffsetSeconds, 0);
      expect((await DbHostCredentialStore(r.pc.db).load())!.hostId, r.phone.id);
      expect(await r.client.reachable(), isTrue);
    });

    test('a PC whose clock is 10 minutes fast is measured, on both ends', () async {
      final w = World();
      final phone = Node('phone', w);
      final pc = Node('pc', w, skew: 600);
      await phone.init();
      await pc.init();
      final server = SyncServer(
        engine: phone.engine,
        certificate: cert,
        blobSource: MemoryBlobStore(),
        blobSink: MemoryBlobStore(),
        deviceName: 'Phone',
        clock: clockOf(phone),
      );
      await server.start(bindTo: InternetAddress.loopbackIPv4);
      addTearDown(() async {
        await server.dispose();
        await phone.close();
        await pc.close();
      });
      final client = SyncClient(
        engine: pc.engine,
        blobSource: MemoryBlobStore(),
        blobSink: MemoryBlobStore(),
        store: DbHostCredentialStore(pc.db),
        deviceName: 'PC',
        clock: clockOf(pc),
      );
      await client.pair(await server.newPairing(host: '127.0.0.1'));
      expect((await phone.engine.peer(pc.id))!.clockOffsetSeconds, closeTo(600, 1));
      expect((await pc.engine.peer(phone.id))!.clockOffsetSeconds, closeTo(-600, 1));
    });

    test('an expired code is refused', () async {
      final r = await Rig.create();
      addTearDown(r.close);
      final p = await r.payload();
      r.world.advance(121);
      await expectLater(r.client.pair(p), throwsA(isA<SyncException>().having((e) => e.code, 'code', 'bad_token')));
      expect(await r.phone.engine.peers(), isEmpty);
    });

    test('a code works once', () async {
      final r = await Rig.create();
      addTearDown(r.close);
      final p = await r.payload();
      await r.client.pair(p);
      await expectLater(r.client.pair(p), throwsA(isA<SyncException>().having((e) => e.code, 'code', 'bad_token')));
    });

    test('a wrong certificate fingerprint is refused before anything is sent', () async {
      final r = await Rig.create();
      addTearDown(r.close);
      final p = await r.payload();
      final wrong = PairingPayload(
        host: p.host,
        port: p.port,
        token: p.token,
        certSha256: '0' * 64,
        deviceName: p.deviceName,
      );
      await expectLater(
        r.client.pair(wrong),
        throwsA(isA<SyncException>().having((e) => e.code, 'code', 'cert_mismatch')),
      );
      expect(await r.phone.engine.peers(), isEmpty);
      // The token was never presented, so the real code still works.
      await r.client.pair(p);
    });

    test('a client that is not on a home network is refused', () async {
      final r = await Rig.create(allowed: (_) => false);
      addTearDown(r.close);
      await expectLater(
        r.client.pair(await r.payload()),
        throwsA(isA<SyncException>().having((e) => e.code, 'code', 'not_on_your_network')),
      );
      expect(await r.client.reachable(), isFalse);
    });

    test('five wrong codes in a minute lock pairing for a minute', () async {
      final r = await Rig.create();
      addTearDown(r.close);
      final p = await r.payload();
      for (var i = 0; i < 5; i++) {
        final bad = PairingPayload(
          host: p.host,
          port: p.port,
          token: 'wrong$i',
          certSha256: p.certSha256,
          deviceName: p.deviceName,
        );
        await expectLater(r.client.pair(bad), throwsA(isA<SyncException>().having((e) => e.code, 'code', 'bad_token')));
      }
      await expectLater(
        r.client.pair(p),
        throwsA(isA<SyncException>().having((e) => e.code, 'code', 'too_many_attempts')),
      );
      r.world.advance(61);
      await r.client.pair(await r.payload());
    });

    test('pairing a second PC unpairs the first (two devices only)', () async {
      final r = await Rig.create();
      addTearDown(r.close);
      await r.pairNow();
      final w = r.world;
      final pc2 = Node('pc2', w);
      await pc2.init();
      addTearDown(pc2.close);
      final client2 = SyncClient(
        engine: pc2.engine,
        blobSource: MemoryBlobStore(),
        blobSink: MemoryBlobStore(),
        store: DbHostCredentialStore(pc2.db),
        deviceName: 'PC two',
        clock: clockOf(pc2),
      );
      await client2.pair(await r.payload());
      expect((await r.phone.engine.peers()).map((p) => p.id), [pc2.id]);
      await expectLater(r.client.sync(), throwsA(isA<SyncException>().having((e) => e.code, 'code', 'unauthorized')));
      await client2.sync();
    });

    test('unpairing from the PC forgets it on both ends; from the phone, the PC is refused', () async {
      final r = await Rig.create();
      addTearDown(r.close);
      await r.pairNow();
      await r.client.unpair();
      expect(await r.phone.engine.peers(), isEmpty);
      expect(await r.pc.engine.peers(), isEmpty);
      await expectLater(r.client.sync(), throwsA(isA<SyncException>().having((e) => e.code, 'code', 'not_paired')));

      await r.pairNow();
      await r.phone.engine.unpair(r.pc.id);
      await SessionStore(r.phone.db).remove(r.pc.id);
      await expectLater(r.client.sync(), throwsA(isA<SyncException>().having((e) => e.code, 'code', 'unauthorized')));
    });
  });

  group('limits', () {
    test('a pairing message over 64 KB is refused', () async {
      final r = await Rig.create();
      addTearDown(r.close);
      final (status, body) = await rawPost(r, '/pair', Uint8List(100 * 1024));
      expect(status, 413);
      expect(body['error'], 'too_large');
    });

    test('changes need a session; a huge change set is refused', () async {
      final r = await Rig.create(maxJson: 2000);
      addTearDown(r.close);
      var (status, _) = await rawPost(r, '/changes', utf8.encode('{}'));
      expect(status, 401);
      final creds = await r.pairNow();
      (status, _) = await rawPost(r, '/changes', Uint8List(5000), session: creds.session);
      expect(status, 413);
    });

    test('more requests than the limit are answered 429', () async {
      final r = await Rig.create(requestsPerMinute: 3);
      addTearDown(r.close);
      final codes = <int>[];
      for (var i = 0; i < 5; i++) {
        final c = HttpClient()..badCertificateCallback = (_, _, _) => true;
        final req = await c.getUrl(Uri.parse('https://127.0.0.1:${r.server.port}/hello'));
        final res = await req.close();
        await res.drain<void>();
        codes.add(res.statusCode);
        c.close(force: true);
      }
      expect(codes, [200, 200, 200, 429, 429]);
    });

    test('a bad image hash and an unknown path are refused', () async {
      final r = await Rig.create();
      addTearDown(r.close);
      final creds = await r.pairNow();
      final c = HttpClient()..badCertificateCallback = (_, _, _) => true;
      addTearDown(() => c.close(force: true));
      Future<int> get(String path) async {
        final req = await c.getUrl(Uri.parse('https://127.0.0.1:${r.server.port}$path'));
        req.headers.set('authorization', 'Bearer ${creds.session}');
        final res = await req.close();
        await res.drain<void>();
        return res.statusCode;
      }

      expect(await get('/blob/not-a-hash'), 400);
      expect(await get('/blob/${'a' * 64}'), 404);
      expect(await get('/nothing'), 404);
    });
  });

  group('a full round', () {
    test('both ways, with images, matches on both sides', () async {
      final r = await Rig.create(pageRows: 3);
      addTearDown(r.close);
      final logoA = r.phoneBlobs.put(Uint8List.fromList(List.generate(300, (i) => i % 251)));
      final logoB = r.pcBlobs.put(Uint8List.fromList(List.generate(500, (i) => (i * 7) % 253)));
      final a1 = await r.phone.person('Ada', company: 'Acme');
      await r.phone.person('Ben', company: 'Acme');
      final b1 = await r.pc.person('Cara', company: 'Blue');
      await r.pc.person('Dan');
      await r.phone.set('people', a1, {'logo_sha256': logoA});
      await r.pc.set('people', b1, {'logo_sha256': logoB});
      await r.pairNow();
      final progress = <String>[];
      final result = await r.client.sync(onProgress: (p) => progress.add(p.phase));
      expect(result.received, greaterThan(0));
      expect(result.sent, greaterThan(0));
      expect(result.imagesDown, 1);
      expect(result.imagesUp, 1);
      expect(progress, containsAll(['connecting', 'receiving', 'sending', 'images', 'finishing']));
      expect(firstDiff(await dump(r.phone.db), await dump(r.pc.db)), 'same');
      expect(await r.phone.count('SELECT COUNT(*) AS n FROM people WHERE deleted_at IS NULL'), 4);
      expect(r.pcBlobs.get(logoA), isNotNull);
      expect(r.phoneBlobs.get(logoB), isNotNull);
      // Nothing new: the second round moves no rows.
      final again = await r.client.sync();
      expect(again.imagesDown + again.imagesUp, 0);
      expect(firstDiff(await dump(r.phone.db), await dump(r.pc.db)), 'same');
    });

    test('edits and deletions travel in later rounds', () async {
      final r = await Rig.create();
      addTearDown(r.close);
      final a = await r.phone.person('Ada', company: 'Acme');
      final b = await r.phone.person('Ben');
      await r.pairNow();
      await r.client.sync();
      r.world.advance(300);
      await r.phone.set('people', a, {'notes': 'met at FabTech'});
      await r.pc.tombstone('people', b);
      r.world.advance(30);
      await r.client.sync();
      expect((await r.pc.row('people', a))!['notes'], 'met at FabTech');
      expect((await r.phone.row('people', b))!['deleted_at'], isNotNull);
      expect(firstDiff(await dump(r.phone.db), await dump(r.pc.db)), 'same');
    });

    test('a link that drops while moving an image resumes where it stopped', () async {
      final r = await Rig.create(chunk: 64 * 1024);
      addTearDown(r.close);
      final big = Uint8List.fromList(List.generate(600 * 1024, (i) => (i * 31 + i ~/ 7) % 256));
      final hash = r.phoneBlobs.put(big);
      final a = await r.phone.person('Ada');
      await r.phone.set('people', a, {'logo_sha256': hash});
      await r.pairNow();
      r.client.debugMaxBlobChunks = 3;
      await expectLater(r.client.sync(), throwsA(isA<SyncException>().having((e) => e.code, 'code', 'interrupted')));
      expect(await r.pcBlobs.received(hash), 3 * 64 * 1024);
      expect(await r.pcBlobs.has(hash), isFalse);
      r.client.debugMaxBlobChunks = null;
      final result = await r.client.sync();
      expect(result.imagesDown, 1);
      expect(r.pcBlobs.get(hash), big);
      expect(await r.phone.count("SELECT COUNT(*) AS n FROM people WHERE deleted_at IS NULL"), 1);
    });

    test('an image uploaded to the phone resumes too', () async {
      final r = await Rig.create(chunk: 64 * 1024);
      addTearDown(r.close);
      final big = Uint8List.fromList(List.generate(400 * 1024, (i) => (i * 13) % 256));
      final hash = r.pcBlobs.put(big);
      final a = await r.pc.person('Cara');
      await r.pc.set('people', a, {'logo_sha256': hash});
      await r.pairNow();
      r.client.debugMaxBlobChunks = 2;
      await expectLater(r.client.sync(), throwsA(isA<SyncException>().having((e) => e.code, 'code', 'interrupted')));
      expect(await r.phoneBlobs.received(hash), 2 * 64 * 1024);
      r.client.debugMaxBlobChunks = null;
      expect((await r.client.sync()).imagesUp, 1);
      expect(r.phoneBlobs.get(hash), big);
    });

    test('a field both sides changed becomes a conflict that stays until chosen, then converges', () async {
      final r = await Rig.create();
      addTearDown(r.close);
      final a = await r.phone.person('Ada', company: 'Acme');
      await r.pairNow();
      await r.client.sync();
      r.world.advance(600);
      await r.phone.set('people', a, {'notes': 'phone says'});
      r.world.advance(20);
      await r.pc.set('people', a, {'notes': 'pc says'});
      r.world.advance(5);
      final result = await r.client.sync();
      expect(result.conflicts, greaterThan(0));
      final pcOpen = await r.pc.engine.conflicts();
      final phoneOpen = await r.phone.engine.conflicts();
      expect(pcOpen.length + phoneOpen.length, greaterThan(0));
      // Each device keeps its own value until someone chooses.
      expect((await r.phone.row('people', a))!['notes'], 'phone says');
      expect((await r.pc.row('people', a))!['notes'], 'pc says');
      // The owner keeps the phone's value everywhere.
      for (final c in phoneOpen) {
        await r.phone.engine.resolveMine(c.id);
      }
      for (final c in pcOpen) {
        await r.pc.engine.resolveTheirs(c.id);
      }
      r.world.advance(30);
      await r.client.sync();
      r.world.advance(30);
      await r.client.sync();
      expect((await r.phone.row('people', a))!['notes'], 'phone says');
      expect((await r.pc.row('people', a))!['notes'], 'phone says');
      expect(await r.phone.engine.openConflictCount(), 0);
      expect(await r.pc.engine.openConflictCount(), 0);
    });

    test('the same round twice is harmless', () async {
      final r = await Rig.create();
      addTearDown(r.close);
      await r.phone.person('Ada', company: 'Acme');
      await r.pc.person('Cara', company: 'Acme');
      await r.pairNow();
      await r.client.sync();
      await r.client.sync();
      await r.client.sync();
      expect(firstDiff(await dump(r.phone.db), await dump(r.pc.db)), 'same');
      expect(await r.phone.count('SELECT COUNT(*) AS n FROM companies WHERE deleted_at IS NULL'), 1);
    });

    test('a PC with the wrong clock still merges correctly', () async {
      final w = World();
      final phone = Node('phone', w);
      final pc = Node('pc', w, skew: 600);
      await phone.init();
      await pc.init();
      final phoneBlobs = MemoryBlobStore();
      final server = SyncServer(
        engine: phone.engine,
        certificate: cert,
        blobSource: phoneBlobs,
        blobSink: phoneBlobs,
        deviceName: 'Phone',
        clock: clockOf(phone),
      );
      await server.start(bindTo: InternetAddress.loopbackIPv4);
      addTearDown(() async {
        await server.dispose();
        await phone.close();
        await pc.close();
      });
      final pcBlobs = MemoryBlobStore();
      final client = SyncClient(
        engine: pc.engine,
        blobSource: pcBlobs,
        blobSink: pcBlobs,
        store: DbHostCredentialStore(pc.db),
        deviceName: 'PC',
        clock: clockOf(pc),
      );
      final a = await phone.person('Ada');
      await client.pair(await server.newPairing(host: '127.0.0.1'));
      await client.sync();
      w.advance(900);
      // The phone edits 5 minutes after the PC did, in true time; the PC clock reads 10 minutes ahead.
      await pc.set('people', a, {'notes': 'pc older'});
      w.advance(300);
      await phone.set('people', a, {'notes': 'phone newer'});
      w.advance(30);
      await client.sync();
      expect((await phone.row('people', a))!['notes'], 'phone newer');
      expect((await pc.row('people', a))!['notes'], 'phone newer');
    });
  });
}
