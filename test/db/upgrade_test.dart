import 'dart:io';

import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sq;

/// A restore of an older backup depends on the upgrade path (audit
/// MOB-REL-0009): a version 1 database, with data, must open as version 3.
void main() {
  test('a schema v1 database with contacts upgrades to v3 and keeps its data', () async {
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
    for (final c in ['middle', 'logo_sha256', 'extras_json']) {
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
}
