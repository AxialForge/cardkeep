import 'dart:convert';
import 'dart:typed_data';

import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/purge.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/sync/blob_transfer.dart';
import 'package:card_organizer/core/sync/change_set.dart';
import 'package:card_organizer/core/sync/sync_engine.dart';
import 'package:card_organizer/core/sync/sync_tables.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_helpers.dart';

/// Two in-memory databases, A and B, each with its own engine, exchanging change
/// sets (0.8 step 1, S16 test list). No network: the sets go through JSON text,
/// as they will on the wire.
void main() {
  late Node a, b;

  Future<void> start({
    int skewB = 0,
    Duration window = const Duration(minutes: 2),
    int pageSize = 5000,
    int? at,
  }) async {
    final p = await pair(skewB: skewB, window: window, pageSize: pageSize, start: at);
    a = p.$1;
    b = p.$2;
  }

  setUp(() => start());
  tearDown(() async {
    await a.close();
    await b.close();
  });

  Future<String> detailed(Node n, String first, {String company = 'Halden Tooling', String notes = ''}) =>
      n.contacts.save(
        ContactDraft(
          first: first,
          last: 'Reyes',
          title: 'Buyer',
          company: company,
          phones: [LabeledValue('Mobile', '330 555 01${first.codeUnitAt(0) % 90 + 10}')],
          emails: ['${first.toLowerCase()}@example.com'],
          notes: notes,
        ),
      );

  Future<String?> notesOf(Node n, String id) async => (await n.row('people', id))?['notes'] as String?;

  test('new contacts travel both ways with their companies, phones, emails and tags', () async {
    final p1 = await detailed(a, 'Dana');
    final hot = await a.tags.create('Hot');
    await a.tags.setTags(p1, {hot});
    final p2 = await detailed(b, 'Sam', company: 'Brightline');
    a.world.advance(5);
    await exchange(a, b);

    for (final n in [a, b]) {
      expect(await n.count('SELECT COUNT(*) AS n FROM people WHERE deleted_at IS NULL'), 2, reason: n.name);
      expect(await n.count('SELECT COUNT(*) AS n FROM companies WHERE deleted_at IS NULL'), 2, reason: n.name);
      expect(await n.count('SELECT COUNT(*) AS n FROM contact_points WHERE deleted_at IS NULL'), 4, reason: n.name);
      expect(await n.count('SELECT COUNT(*) AS n FROM person_tags WHERE deleted_at IS NULL'), 1, reason: n.name);
    }
    expect(await b.row('people', p1), isNotNull);
    expect(await a.row('people', p2), isNotNull);
    expect(await dump(a.db), await dump(b.db));
  });

  test('an edit on one side reaches the other, with the editor\'s time', () async {
    final p1 = await detailed(a, 'Dana');
    await exchange(a, b);
    a.world.advance(600);
    await a.set('people', p1, {'notes': 'call back Friday'});
    final res = await send(a, b);
    expect(res.updated, 1);
    expect(await notesOf(b, p1), 'call back Friday');
    expect((await b.row('people', p1))!['updated_at'], (await a.row('people', p1))!['updated_at']);
  });

  test('a deletion travels as a tombstone', () async {
    final p1 = await detailed(a, 'Dana');
    await exchange(a, b);
    a.world.advance(600);
    await a.contacts.delete(p1);
    final res = await send(a, b);
    expect(res.deleted, 1);
    expect((await b.row('people', p1))!['deleted_at'], isNotNull);
  });

  group('a deletion against an edit: the later one wins, a tie goes to the deletion', () {
    Future<String> synced() async {
      final p = await detailed(a, 'Dana');
      await exchange(a, b);
      a.world.advance(1000);
      return p;
    }

    test('edit is later: the contact comes back with the edit', () async {
      final p = await synced();
      await a.tombstone('people', p);
      a.world.advance(300);
      await b.set('people', p, {'notes': 'still a customer'});
      await exchange(a, b);
      for (final n in [a, b]) {
        expect((await n.row('people', p))!['deleted_at'], isNull, reason: n.name);
        expect(await notesOf(n, p), 'still a customer', reason: n.name);
      }
    });

    test('deletion is later: it stays deleted on both', () async {
      final p = await synced();
      await b.set('people', p, {'notes': 'edited'});
      a.world.advance(300);
      await a.tombstone('people', p);
      await exchange(a, b);
      for (final n in [a, b]) {
        expect((await n.row('people', p))!['deleted_at'], isNotNull, reason: n.name);
      }
    });

    test('same second: the deletion wins', () async {
      final p = await synced();
      await a.tombstone('people', p, at: a.t);
      await b.set('people', p, {'notes': 'edited'}, at: a.t);
      await exchange(a, b);
      for (final n in [a, b]) {
        expect((await n.row('people', p))!['deleted_at'], isNotNull, reason: n.name);
      }
    });
  });

  group('the same field changed on both sides close together is a conflict', () {
    late String p;
    setUp(() async {
      p = await detailed(a, 'Dana');
      await exchange(a, b);
      a.world.advance(1000);
      await a.set('people', p, {'notes': 'A says'});
      a.world.advance(30);
      await b.set('people', p, {'notes': 'B says'});
      await exchange(a, b);
    });

    test('both keep their own value and list the conflict', () async {
      expect(await notesOf(a, p), 'A says');
      expect(await notesOf(b, p), 'B says');
      final ca = await a.engine.conflicts();
      final cb = await b.engine.conflicts();
      expect(ca, hasLength(1));
      expect(cb, hasLength(1));
      expect((ca.single.table, ca.single.rowKey, ca.single.field), ('people', p, 'notes'));
      expect((ca.single.mine, ca.single.theirs), ('A says', 'B says'));
      expect((cb.single.mine, cb.single.theirs), ('B says', 'A says'));
      expect(await a.engine.openConflictCount(), 1);
    });

    test('exchanging again does not pile up duplicates or flip a value', () async {
      await exchange(a, b);
      await exchange(a, b);
      expect(await a.engine.openConflictCount(), 1);
      expect(await b.engine.openConflictCount(), 1);
      expect(await notesOf(a, p), 'A says');
      expect(await notesOf(b, p), 'B says');
    });

    test('keep mine: the other device takes it and both conflicts close', () async {
      a.world.advance(600);
      await a.engine.resolveMine((await a.engine.conflicts()).single.id);
      expect(await a.engine.openConflictCount(), 0);
      await exchange(a, b);
      expect(await notesOf(b, p), 'A says');
      expect(await notesOf(a, p), 'A says');
      expect(await b.engine.openConflictCount(), 0, reason: 'the same value on both ends closes it');
      expect((await a.engine.conflicts(openOnly: false)).single.resolution, 'mine');
    });

    test('take theirs: this device changes, and the choice reaches the other one', () async {
      a.world.advance(600);
      await a.engine.resolveTheirs((await a.engine.conflicts()).single.id);
      expect(await notesOf(a, p), 'B says');
      await exchange(a, b);
      expect(await notesOf(b, p), 'B says');
      expect(await b.engine.openConflictCount(), 0);
      expect((await a.engine.conflicts(openOnly: false)).single.resolution, 'theirs');
    });
  });

  test('edits to different fields of the same row both stay, with no conflict', () async {
    final p = await detailed(a, 'Dana');
    await exchange(a, b);
    a.world.advance(1000);
    await a.set('people', p, {'notes': 'from A'});
    a.world.advance(5);
    await b.set('people', p, {'hours': 'Mon-Fri 9-5'});
    await exchange(a, b);
    await exchange(a, b);
    for (final n in [a, b]) {
      final r = (await n.row('people', p))!;
      expect((r['notes'], r['hours']), ('from A', 'Mon-Fri 9-5'), reason: n.name);
      expect(await n.engine.openConflictCount(), 0, reason: n.name);
    }
    expect(await dump(a.db), await dump(b.db));
  });

  test('the same field edited far apart in time: the later edit wins, no conflict', () async {
    final p = await detailed(a, 'Dana');
    await exchange(a, b);
    a.world.advance(1000);
    await a.set('people', p, {'notes': 'first'});
    a.world.advance(500);
    await b.set('people', p, {'notes': 'second'});
    await exchange(a, b);
    expect(await notesOf(a, p), 'second');
    expect(await notesOf(b, p), 'second');
    expect(await a.engine.openConflictCount() + await b.engine.openConflictCount(), 0);
  });

  group('a phone with the wrong clock', () {
    for (final skew in [600, -600]) {
      test(
        '${skew > 0 ? 'ahead' : 'behind'} by 10 minutes: the offset set at pairing puts its edit in true order',
        () async {
          await a.close();
          await b.close();
          await start(skewB: skew);
          final p = await detailed(a, 'Dana');
          await exchange(a, b);
          a.world.advance(1000);
          // Real time: B edits first, then A edits 300 s later, so A should win.
          await b.set('people', p, {'notes': 'B early'});
          a.world.advance(300);
          await a.set('people', p, {'notes': 'A late'});
          await exchange(a, b);
          expect(await notesOf(a, p), 'A late');
          expect(await notesOf(b, p), 'A late');
        },
      );

      test('${skew > 0 ? 'ahead' : 'behind'}: without the offset the older edit would wrongly win', () async {
        await a.close();
        await b.close();
        await start(skewB: skew);
        // Pretend pairing measured no offset.
        await a.engine.registerPeer(b.id, name: 'B', clockOffsetSeconds: 0);
        await b.engine.registerPeer(a.id, name: 'A', clockOffsetSeconds: 0);
        final p = await detailed(a, 'Dana');
        await exchange(a, b);
        a.world.advance(1000);
        await b.set('people', p, {'notes': 'B early'});
        a.world.advance(300);
        await a.set('people', p, {'notes': 'A late'});
        await exchange(a, b);
        final notes = {await notesOf(a, p), await notesOf(b, p)};
        expect(
          notes,
          skew > 0 ? {'B early'} : {'A late'},
          reason: 'the control: skew without correction mis-orders the edits',
        );
      });
    }
  });

  group('transfers that stop part way', () {
    test('a big set in pages arrives whole, and only the last page moves the watermark', () async {
      for (var i = 0; i < 12; i++) {
        await detailed(a, 'P${String.fromCharCode(65 + i)}${i}x', company: 'Co${i % 4}');
      }
      a.world.advance(5);
      var pages = 0;
      String? cursor;
      late ChangeSet last;
      do {
        last = await a.engine.buildChanges(peerId: b.id, cursor: cursor, limit: 9);
        pages++;
        final res = await b.engine.apply(ChangeSet.decode(last.encode()));
        expect(res.complete, last.isLast);
        if (!last.isLast) expect((await b.engine.peer(a.id))!.theirWatermark, 0, reason: 'not done yet');
        await a.engine.acknowledge(b.id, last, peerConflicts: res.conflicts);
        cursor = last.next;
      } while (cursor != null);
      expect(pages, greaterThan(3));
      expect((await b.engine.peer(a.id))!.theirWatermark, last.until);
      expect(await dump(b.db), await dump(a.db));
    });

    test('applying half and then everything gives the same result as applying everything once', () async {
      for (var i = 0; i < 8; i++) {
        await detailed(a, 'Q${String.fromCharCode(65 + i)}', company: 'Firm${i % 3}');
      }
      a.world.advance(5);
      final whole = await a.engine.buildChanges(peerId: b.id);
      final pieces = whole.split(6);
      expect(pieces.length, greaterThan(2));
      await b.engine.apply(pieces[0]);
      await b.engine.apply(pieces[1]);
      expect((await b.engine.peer(a.id))!.theirWatermark, 0, reason: 'the link dropped before the last piece');
      // Resume: send it all again.
      for (final p in pieces) {
        await b.engine.apply(p);
      }
      expect((await b.engine.peer(a.id))!.theirWatermark, whole.until);
      await a.engine.acknowledge(b.id, whole);
      expect(await dump(b.db), await dump(a.db));
    });

    test('a set that cannot be applied changes nothing', () async {
      final bad = ChangeSet(
        deviceId: a.id,
        since: 0,
        until: a.t,
        tables: {
          'people': [
            {'uuid': 'good', 'first': 'Ok', 'created_at': 1, 'updated_at': 2, 'deleted_at': null},
          ],
          'roles': [
            {'uuid': 'broken', 'person_id': null, 'created_at': 1, 'updated_at': 2, 'deleted_at': null},
          ],
        },
      );
      await expectLater(b.engine.apply(bad), throwsA(anything));
      expect(await b.count('SELECT COUNT(*) AS n FROM people'), 0, reason: 'rolled back as a whole');
      expect(await b.count("SELECT COUNT(*) AS n FROM app_settings WHERE key = 'sync.applying'"), 0);
      // And the next real apply still stamps nothing it should not.
      await detailed(a, 'Fine');
      await send(a, b);
      expect(await b.count('SELECT COUNT(*) AS n FROM people'), 1);
    });
  });

  test('applying the same set again does nothing', () async {
    await detailed(a, 'Dana');
    await detailed(b, 'Sam', company: 'Brightline');
    a.world.advance(5);
    await exchange(a, b);
    final before = (await dump(a.db, stamps: true), await dump(b.db, stamps: true));
    final cs = await a.engine.buildChanges(peerId: b.id, since: 0);
    final again = await b.engine.apply(cs);
    expect(again.changes, 0);
    expect(again.conflicts, isEmpty);
    await exchange(a, b);
    final afterA = await dump(a.db, stamps: true);
    final afterB = await dump(b.db, stamps: true);
    expect(firstDiff(before.$1, afterA), 'same', reason: 'A changed');
    expect(firstDiff(before.$2, afterB), 'same', reason: 'B changed');
  });

  group('same thing made on both devices becomes one', () {
    test('a company', () async {
      final pa = await detailed(a, 'Dana', company: 'Acme');
      final pb = await detailed(b, 'Sam', company: 'Acme');
      a.world.advance(5);
      await exchange(a, b);
      await exchange(a, b);
      for (final n in [a, b]) {
        final live = await n.db
            .customSelect("SELECT uuid FROM companies WHERE name_norm = 'acme' AND deleted_at IS NULL")
            .get();
        expect(live, hasLength(1), reason: n.name);
        final co = live.single.read<String>('uuid');
        expect(
          await n.count("SELECT COUNT(*) AS n FROM roles WHERE company_id = '$co' AND deleted_at IS NULL"),
          2,
          reason: n.name,
        );
      }
      expect(await dump(a.db), await dump(b.db));
      expect(pa, isNot(pb));
    });

    test('a tag, and a person given it on both sides keeps one link', () async {
      final p = await detailed(a, 'Dana');
      await exchange(a, b);
      a.world.advance(100);
      final hotA = await a.tags.create('Hot');
      final hotB = await b.tags.create('hot');
      await a.tags.setTags(p, {hotA});
      await b.tags.setTags(p, {hotB});
      a.world.advance(5);
      await exchange(a, b);
      await exchange(a, b);
      for (final n in [a, b]) {
        expect(await n.count('SELECT COUNT(*) AS n FROM tags WHERE deleted_at IS NULL'), 1, reason: n.name);
        expect(
          await n.count('SELECT COUNT(*) AS n FROM person_tags WHERE person_id = \'$p\' AND deleted_at IS NULL'),
          1,
          reason: n.name,
        );
        expect(
          await n.count('SELECT COUNT(*) AS n FROM person_tags'),
          1,
          reason: '${n.name}: no leftover duplicate row',
        );
      }
      expect(await dump(a.db), await dump(b.db));
    });

    test('a place category with the same label, and the places that use it', () async {
      await a.db.customStatement("INSERT INTO place_categories (id, label, sort) VALUES ('c_a', 'Bakery', 7)");
      await b.db.customStatement("INSERT INTO place_categories (id, label, sort) VALUES ('c_b', 'bakery', 7)");
      final pb = await b.contacts.save(ContactDraft(company: 'Rye Co', kind: PersonKind.place, category: 'c_b'));
      a.world.advance(5);
      await exchange(a, b);
      await exchange(a, b);
      for (final n in [a, b]) {
        final live = await n.db
            .customSelect("SELECT id FROM place_categories WHERE lower(label) = 'bakery' AND deleted_at IS NULL")
            .get();
        expect(live, hasLength(1), reason: n.name);
        expect(live.single.read<String>('id'), 'c_a', reason: 'the smaller id stays');
        expect((await n.row('people', pb))!['place_category'], 'c_a', reason: n.name);
      }
    });

    test('a deleted place category is a tombstone on the other device too', () async {
      await a.db.customStatement("INSERT INTO place_categories (id, label, sort) VALUES ('c_x', 'Florist', 7)");
      await exchange(a, b);
      expect(await b.row('place_categories', 'c_x'), isNotNull);
      a.world.advance(600);
      await a.tombstone('place_categories', 'c_x');
      await exchange(a, b);
      expect((await b.row('place_categories', 'c_x'))!['deleted_at'], isNotNull);
    });
  });

  test('a purged contact reaches the other device as a blank tombstone, and the purge does not resurrect it', () async {
    // The purge's updated_at is stamped by the database's own (real) clock, so
    // this test starts the fake time in the past and lets real time be "later".
    await a.close();
    await b.close();
    await start(at: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 30 * 86400);
    final p = await detailed(a, 'Dana', notes: 'secret');
    await exchange(a, b);
    a.world.advance(10 * 86400);
    await a.contacts.delete(p);
    a.world.advance(10 * 86400);
    final purged = await purgeDeleted(a.db, before: DateTime.fromMillisecondsSinceEpoch(a.t * 1000 - 7 * 86400 * 1000));
    expect(purged.people, 1);
    await exchange(a, b);
    var r = (await b.row('people', p))!;
    expect(r['deleted_at'], isNotNull);
    expect(r['notes'], '');
    expect(r['display_name'], '');
    // The other device's own purge clears what it still holds for that person.
    await purgeDeleted(b.db, before: DateTime.fromMillisecondsSinceEpoch(b.t * 1000 + 86400000));
    expect(await b.count("SELECT COUNT(*) AS n FROM contact_points WHERE person_id = '$p'"), 0);
    await exchange(a, b);
    await exchange(a, b);
    r = (await b.row('people', p))!;
    expect(r['deleted_at'], isNotNull, reason: 'syncing again does not bring it back');
    expect((await a.row('people', p))!['deleted_at'], isNotNull);
  });

  test(
    'images: the change set names them, missing ones are listed, a dropped transfer resumes, a bad one is refused',
    () async {
      final storeA = MemoryBlobStore();
      final storeB = MemoryBlobStore();
      final front = storeA.put(Uint8List.fromList(List<int>.generate(1000, (i) => i % 251)));
      final back = storeA.put(Uint8List.fromList(List<int>.generate(300, (i) => (i * 7) % 253)));
      final p = await detailed(a, 'Dana');
      await a.db.customStatement(
        'INSERT INTO cards (uuid, person_id, front_sha256, back_sha256, status) VALUES (?, ?, ?, ?, ?)',
        ['card1', p, front, back, 'saved'],
      );
      a.world.advance(5);
      final cs = await a.engine.buildChanges(peerId: b.id);
      expect(cs.blobs, containsAll([front, back]));

      final eb = SyncEngine(b.db, blobs: storeB, clock: () => DateTime.fromMillisecondsSinceEpoch((a.t + 1) * 1000));
      final res = await eb.apply(ChangeSet.decode(cs.encode()));
      expect(res.blobsNeeded, unorderedEquals([front, back]));
      expect(
        (await b.row('cards', 'card1'))!['front_sha256'],
        front,
        reason: 'the reference arrives even before the image',
      );

      // The link drops after two 100-byte chunks.
      expect(await transferBlob(storeA, storeB, front, chunkSize: 100, maxChunks: 2), isFalse);
      expect(await storeB.received(front), 200);
      expect(await storeB.has(front), isFalse);
      // Resume from byte 200.
      expect(await transferBlob(storeA, storeB, front, chunkSize: 100), isTrue);
      expect(storeB.get(front), storeA.get(front));
      expect(await missingBlobs(storeB, [front, back, front]), [back], reason: 'once each, only what is missing');

      // A chunk at the wrong offset is refused.
      await storeB.write(back, 0, storeA.get(back)!.sublist(0, 50));
      await expectLater(storeB.write(back, 0, storeA.get(back)!.sublist(0, 50)), throwsStateError);
      // A blob whose bytes do not match its hash never becomes a blob.
      final other = MemoryBlobStore();
      await other.write(back, 0, Uint8List.fromList(List<int>.filled(300, 1)));
      expect(await other.commit(back), isFalse);
      expect(await other.has(back), isFalse);
    },
  );

  test('500 contacts: one change set, a few MB at most, applied in seconds', () async {
    final sw = Stopwatch()..start();
    final now = a.t;
    await a.db.transaction(() async {
      for (var c = 0; c < 20; c++) {
        await a.db.customStatement(
          'INSERT INTO companies (uuid, name, name_norm, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
          ['co$c', 'Company $c', 'company $c', now, now],
        );
      }
      for (var i = 0; i < 500; i++) {
        await a.db.customStatement(
          'INSERT INTO people (uuid, first, last, display_name, notes, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
          ['p$i', 'First$i', 'Last$i', 'First$i Last$i', 'notes for contact number $i', now, now],
        );
        await a.db.customStatement(
          'INSERT INTO roles (uuid, person_id, company_id, title, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
          ['r$i', 'p$i', 'co${i % 20}', 'Buyer', now, now],
        );
        for (var k = 0; k < 2; k++) {
          await a.db.customStatement(
            'INSERT INTO contact_points (uuid, person_id, role_id, kind, value, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [
              'cp${i}_$k',
              'p$i',
              'r$i',
              k == 0 ? 'mobile' : 'email',
              k == 0 ? '330555${1000 + i}' : 'p$i@example.com',
              now,
              now,
            ],
          );
        }
      }
    });
    final cs = await a.engine.buildChanges(peerId: b.id);
    final text = cs.encode();
    expect(cs.rowCount, 5 + 20 + 500 + 500 + 1000, reason: 'the five built-in place categories are in every first set');
    expect(text.length, lessThan(2 * 1024 * 1024), reason: 'wire size ${text.length} bytes');
    final res = await b.engine.apply(ChangeSet.decode(text));
    expect(res.inserted, 20 + 500 + 500 + 1000, reason: 'the built-in categories were already there');
    expect(await b.count('SELECT COUNT(*) AS n FROM people'), 500);
    expect(await b.count('SELECT COUNT(*) AS n FROM contact_points'), 1000);
    expect(sw.elapsed, lessThan(const Duration(seconds: 30)), reason: 'took ${sw.elapsed}');
  });

  group('what a change set may and may not be', () {
    test('a newer format is refused, damage is reported, unknown columns are ignored', () async {
      final newer = jsonEncode({'v': 99, 'device_id': 'x', 'since': 0, 'until': 1, 'tables': {}});
      expect(() => ChangeSet.decode(newer), throwsA(isA<SyncFormatException>()));
      expect(() => ChangeSet.decode('not json'), throwsA(isA<SyncFormatException>()));
      expect(() => ChangeSet.decode('{"v":1}'), throwsA(isA<SyncFormatException>()));

      final withFuture = ChangeSet(
        deviceId: a.id,
        since: 0,
        until: a.t,
        tables: {
          'people': [
            {
              'uuid': 'f1',
              'first': 'Zed',
              'created_at': 1,
              'updated_at': 5,
              'deleted_at': null,
              'a_future_column': 'x',
            },
          ],
        },
      );
      await b.engine.apply(withFuture);
      expect((await b.row('people', 'f1'))!['first'], 'Zed');
    });

    test('a device does not apply its own change set', () async {
      final own = await a.engine.buildChanges();
      await expectLater(a.engine.apply(own), throwsA(isA<SyncFormatException>()));
    });

    test('a row whose parent is nowhere is skipped, not a crash', () async {
      final cs = ChangeSet(
        deviceId: a.id,
        since: 0,
        until: a.t,
        tables: {
          'roles': [
            {'uuid': 'r1', 'person_id': 'ghost', 'title': 'x', 'created_at': 1, 'updated_at': 5, 'deleted_at': null},
          ],
        },
      );
      final res = await b.engine.apply(cs);
      expect(res.orphans, 1);
      expect(await b.count('SELECT COUNT(*) AS n FROM roles'), 0);
    });

    test('a peer\'s time in the future is held to now', () async {
      final cs = ChangeSet(
        deviceId: a.id,
        since: 0,
        until: a.t,
        tables: {
          'people': [
            {'uuid': 'f2', 'first': 'Late', 'created_at': 1, 'updated_at': a.t + 99999, 'deleted_at': null},
          ],
        },
      );
      await b.engine.apply(cs);
      expect((await b.row('people', 'f2'))!['updated_at'] as int, lessThanOrEqualTo(b.t));
    });

    test('every synced table has an entry in the dump so a new one cannot slip past these tests', () async {
      expect((await dump(a.db)).keys, syncTables.map((t) => t.name));
    });
  });

  test('unpairing forgets the device and what was known about it', () async {
    await detailed(a, 'Dana');
    await exchange(a, b);
    expect(await a.count('SELECT COUNT(*) AS n FROM sync_base'), greaterThan(0));
    await a.engine.unpair(b.id);
    expect(await a.engine.peer(b.id), isNull);
    expect(await a.count('SELECT COUNT(*) AS n FROM sync_base'), 0);
    expect(await a.engine.peers(), isEmpty);
  });

  test('blob names come only from live rows', () async {
    final p = await detailed(a, 'Dana');
    await a.db.customStatement(
      'INSERT INTO cards (uuid, person_id, front_sha256, status, deleted_at) VALUES (?, ?, ?, ?, ?)',
      ['gone', p, 'deadbeef', 'saved', a.t],
    );
    final cs = await a.engine.buildChanges(peerId: b.id);
    expect(cs.blobs, isNot(contains('deadbeef')));
  });
}
