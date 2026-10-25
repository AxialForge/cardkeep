import 'dart:io';

import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/contacts/place_category_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/sync/sync_engine.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sq;

/// A restore of an older backup depends on the upgrade path (audit
/// MOB-REL-0009): a version 1 or 3 database, with data, must open as today's version.
void main() {
  test('a schema v1 database with contacts upgrades and keeps its data', () async {
    final dir = await Directory.systemTemp.createTemp('ck_upgrade');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'v1.sqlite'));

    // Today's schema with one contact, then taken back to v1: the tables and
    // columns v2 and v3 added are removed.
    var db = AppDatabase(NativeDatabase(file));
    await ContactsRepository(db)
        .save(ContactDraft(first: 'Dana', last: 'Reyes', company: 'Halden', emails: ['dana@halden.example']));
    await db.close();
    final raw = sq.sqlite3.open(file.path);
    raw.execute('DROP TABLE not_duplicates');
    raw.execute('DROP TABLE place_categories');
    for (final c in ['middle', 'logo_sha256', 'extras_json', 'kind', 'place_category', 'hours']) {
      raw.execute('ALTER TABLE people DROP COLUMN $c');
    }
    raw.execute('ALTER TABLE contact_points DROP COLUMN extension');
    raw.execute('PRAGMA user_version = 1');
    raw.close();

    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final people = await ContactsRepository(db).watchContacts(const ContactFilter()).first;
    expect(people.map((c) => c.displayName), ['Dana Reyes']);
    final cols = {for (final r in await db.customSelect('PRAGMA table_info(people)').get()) r.read<String>('name')};
    expect(cols, containsAll(['middle', 'logo_sha256', 'extras_json']));
    expect(
      await db.customSelect('SELECT COUNT(*) AS n FROM not_duplicates').getSingle().then((r) => r.read<int>('n')),
      0,
    );
    expect(
      await db.customSelect('PRAGMA user_version').getSingle().then((r) => r.read<int>('user_version')),
      db.schemaVersion,
    );
  });

  test('a schema v3 database upgrades to v4 and every existing contact is a person (S14b.1)', () async {
    final dir = await Directory.systemTemp.createTemp('ck_upgrade');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'v3.sqlite'));

    var db = AppDatabase(NativeDatabase(file));
    await ContactsRepository(db).save(ContactDraft(first: 'Dana', last: 'Reyes', company: 'Halden'));
    await db.close();
    final raw = sq.sqlite3.open(file.path);
    raw.execute('DROP TABLE place_categories');
    for (final c in ['kind', 'place_category', 'hours']) {
      raw.execute('ALTER TABLE people DROP COLUMN $c');
    }
    raw.execute('PRAGMA user_version = 3');
    raw.close();

    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final row = await db.customSelect('SELECT kind, place_category, hours FROM people').getSingle();
    expect(row.read<String>('kind'), 'person');
    expect(row.readNullable<String>('place_category'), isNull);
    expect(row.read<String>('hours'), '');
    final people = await ContactsRepository(db).watchContacts(const ContactFilter()).first;
    expect(people.single.isPlace, isFalse);
  });

  test(
    'a schema v4 database upgrades to v5: the built-in categories are added and places keep theirs (S14b.6)',
    () async {
      final dir = await Directory.systemTemp.createTemp('ck_upgrade');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'v4.sqlite'));

      var db = AppDatabase(NativeDatabase(file));
      await ContactsRepository(db)
          .save(ContactDraft(kind: PersonKind.place, company: 'Lakeside Hardware', category: 'store'));
      await db.close();
      final raw = sq.sqlite3.open(file.path);
      raw.execute('DROP TABLE place_categories');
      raw.execute('PRAGMA user_version = 4');
      raw.close();

      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final ids = [for (final r in await db.select(db.placeCategories).get()) r.id];
      expect(ids, containsAll(PlaceCategory.values.map((c) => c.name)));
      final people = await ContactsRepository(db).watchContacts(const ContactFilter()).first;
      expect(people.single.category, 'store');
      expect(people.single.subtitle, 'Store');
    },
  );

  test(
    'a schema v5 database upgrades to v6 for sync: nothing is lost, new columns, tables and triggers appear (S16.1)',
    () async {
      final dir = await Directory.systemTemp.createTemp('ck_upgrade');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'v5.sqlite'));

      var db = AppDatabase(NativeDatabase(file));
      final contacts = ContactsRepository(db);
      final dana = await contacts.save(
        ContactDraft(first: 'Dana', last: 'Reyes', company: 'Halden', emails: ['dana@halden.example']),
      );
      final bakery = await PlaceCategoryRepository(db).add('Bakery');
      final rye = await contacts.save(ContactDraft(kind: PersonKind.place, company: 'Rye Co', category: bakery));
      await db.close();

      // Take it back to v5: no sync tables, triggers or columns.
      final raw = sq.sqlite3.open(file.path);
      for (final r in raw.select("SELECT name FROM sqlite_master WHERE type = 'trigger'")) {
        raw.execute('DROP TRIGGER ${r['name']}');
      }
      raw.execute('DROP TABLE sync_conflicts');
      raw.execute('DROP TABLE sync_base');
      for (final c in ['updated_at', 'deleted_at']) {
        raw.execute('ALTER TABLE place_categories DROP COLUMN $c');
      }
      for (final c in ['their_watermark', 'my_watermark', 'paired_at', 'clock_offset_seconds']) {
        raw.execute('ALTER TABLE devices DROP COLUMN $c');
      }
      raw.execute('PRAGMA user_version = 5');
      raw.close();

      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      expect(
        await db.customSelect('PRAGMA user_version').getSingle().then((r) => r.read<int>('user_version')),
        db.schemaVersion,
      );
      Future<Set<String>> cols(String t) async => {
        for (final r in await db.customSelect('PRAGMA table_info($t)').get()) r.read<String>('name'),
      };
      expect(await cols('place_categories'), containsAll(['updated_at', 'deleted_at']));
      expect(
        await cols('devices'),
        containsAll(['their_watermark', 'my_watermark', 'paired_at', 'clock_offset_seconds']),
      );
      final tables = {
        for (final r in await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get())
          r.read<String>('name'),
      };
      expect(tables, containsAll(['sync_conflicts', 'sync_base']));
      final triggers = {
        for (final r in await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'trigger'").get())
          r.read<String>('name'),
      };
      expect(triggers, contains('trg_people_touch'));
      expect(triggers, contains('trg_place_categories_touch'));

      // The data is all there, and the owner's own category is stamped so it syncs.
      final list = await ContactsRepository(db).watchContacts(const ContactFilter()).first;
      expect(list.map((c) => c.displayName), containsAll(['Dana Reyes', 'Rye Co']));
      final cat = await db
          .customSelect("SELECT updated_at, deleted_at FROM place_categories WHERE id = '$bakery'")
          .getSingle();
      expect(cat.read<int>('updated_at'), greaterThan(1000000000));
      expect(cat.read<int?>('deleted_at'), isNull);
      expect(
        await db
            .customSelect("SELECT updated_at AS u FROM place_categories WHERE id = 'store'")
            .getSingle()
            .then((r) => r.read<int>('u')),
        0,
        reason: 'built-ins stay 0 on every phone',
      );
      // And the engine can read it all.
      final cs = await SyncEngine(db).buildChanges();
      expect(cs.tables['people']!.map((r) => r['uuid']), containsAll([dana, rye]));
      expect(cs.tables['place_categories']!.map((r) => r['id']), contains(bakery));
    },
  );
}
