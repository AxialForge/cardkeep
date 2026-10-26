import 'dart:io';

import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/data/delete_everything.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/db/pre_upgrade_copy.dart';
import 'package:card_organizer/core/tags/tags_repository.dart';
import 'package:card_organizer/core/transfer/backup.dart';
import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sq;

/// The library is copied aside, byte for byte, before SQLite upgrades it, and
/// an upgrade must never change how many rows any table holds.

/// Takes a database created by today's code back to schema v5 (no sync tables,
/// triggers or columns), the shape the owner's phone had before the update.
void downgradeToV5(File file) {
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
}

/// A v5 library with a bit of everything in it.
Future<File> makeV5(Directory docs) async {
  final file = File(p.join(docs.path, dbFileName));
  final db = AppDatabase(NativeDatabase(file));
  final contacts = ContactsRepository(db);
  final dana = await contacts.save(
    ContactDraft(
      first: 'Dana',
      last: 'Reyes',
      company: 'Halden',
      emails: ['dana@halden.example'],
      phones: [const LabeledValue('Office', '440 510 0108')],
    ),
  );
  await contacts.save(ContactDraft(first: 'Sam', last: 'Okafor', company: 'Brightline'));
  await contacts.save(ContactDraft(first: 'Priya', last: 'Natarajan', company: 'Halden'));
  await contacts.save(ContactDraft(kind: PersonKind.place, company: 'Lakeside Hardware', category: 'store'));
  final tags = TagsRepository(db, contacts);
  final tag = await tags.create('Customers');
  await tags.addToAll([dana], tag);
  await db
      .into(db.events)
      .insert(
        EventsCompanion.insert(
          name: 'FabTech',
          type: EventType.tradeShow,
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 2),
        ),
      );
  await db.into(db.cards).insert(CardsCompanion.insert(frontSha256: 'abc123'));
  await db.into(db.cards).insert(CardsCompanion.insert(frontSha256: 'def456', personId: Value(dana)));
  await db.into(db.notDuplicates).insert(NotDuplicatesCompanion.insert(pairKey: 'a|b'));
  await db.into(db.appSettings).insert(AppSettingsCompanion.insert(key: 'theme', value: 'dark'));
  await db.close();
  downgradeToV5(file);
  return file;
}

Map<String, int> rowCounts(File file) {
  final raw = sq.sqlite3.open(file.path, mode: sq.OpenMode.readOnly);
  try {
    final out = <String, int>{};
    for (final r in raw.select("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")) {
      final t = r['name'] as String;
      out[t] = raw.select('SELECT COUNT(*) AS n FROM "$t"').first['n'] as int;
    }
    return out;
  } finally {
    raw.close();
  }
}

void main() {
  late Directory docs;
  setUp(() async => docs = await Directory.systemTemp.createTemp('ck_preup'));
  tearDown(() => docs.delete(recursive: true));

  test('a v5 library is copied byte for byte before it is upgraded, and only once', () async {
    final file = await makeV5(docs);
    final before = file.readAsBytesSync();

    final copy = await copyBeforeUpgrade(docs, targetVersion: AppDatabase.currentSchemaVersion);
    expect(copy, isNotNull);
    expect(copy!.fromVersion, 5);
    expect(p.basename(copy.dir.path), startsWith('v5-'));
    expect(File(p.join(copy.dir.path, dbFileName)).readAsBytesSync(), before);
    expect(File(p.join(copy.dir.path, '.made')).existsSync(), isTrue);
    expect(listUpgradeCopies(docs), hasLength(1));

    // The upgrade runs; the file is now current.
    final db = AppDatabase(NativeDatabase(file));
    await db.customSelect('SELECT 1').get();
    await db.close();
    expect(readSchemaVersion(file), AppDatabase.currentSchemaVersion);

    // The second start copies nothing, and the copy is untouched.
    expect(await copyBeforeUpgrade(docs, targetVersion: AppDatabase.currentSchemaVersion), isNull);
    expect(listUpgradeCopies(docs), hasLength(1));
    expect(File(p.join(copy.dir.path, dbFileName)).readAsBytesSync(), before);
  });

  test('nothing is copied when there is no library yet or it is already current', () async {
    expect(await copyBeforeUpgrade(docs, targetVersion: 6), isNull);
    final file = File(p.join(docs.path, dbFileName));
    final db = AppDatabase(NativeDatabase(file));
    await db.customSelect('SELECT 1').get();
    await db.close();
    expect(await copyBeforeUpgrade(docs, targetVersion: AppDatabase.currentSchemaVersion), isNull);
    expect(upgradeCopiesDir(docs).existsSync(), isFalse);
  });

  test('the -wal and -shm files are copied with the database', () async {
    final file = await makeV5(docs);
    File('${file.path}-wal').writeAsBytesSync([1, 2, 3, 4, 5]);
    File('${file.path}-shm').writeAsBytesSync([9, 8, 7]);
    final copy = (await copyBeforeUpgrade(docs, targetVersion: 6))!;
    expect(File(p.join(copy.dir.path, '$dbFileName-wal')).readAsBytesSync(), [1, 2, 3, 4, 5]);
    expect(File(p.join(copy.dir.path, '$dbFileName-shm')).readAsBytesSync(), [9, 8, 7]);
    expect(copy.bytes, file.lengthSync() + 5 + 3);
  });

  test('the newest two are kept, and anything older than 14 days goes', () async {
    await makeV5(docs);
    final t = DateTime(2026, 10, 1, 12);
    for (final i in [0, 1, 2]) {
      await copyBeforeUpgrade(docs, targetVersion: 6, now: t.add(Duration(minutes: i)));
    }
    final kept = listUpgradeCopies(docs);
    expect(kept, hasLength(2));
    expect(kept.first.made, t.add(const Duration(minutes: 2)));
    expect(kept.last.made, t.add(const Duration(minutes: 1)));

    // 20 days on, the old two are past 14 days; only the new copy remains.
    await copyBeforeUpgrade(docs, targetVersion: 6, now: t.add(const Duration(days: 20)));
    final later = listUpgradeCopies(docs);
    expect(later, hasLength(1));
    expect(later.single.made, t.add(const Duration(days: 20)));
  });

  test('an interrupted copy (no marker) is not offered and is cleaned up', () async {
    await makeV5(docs);
    final half = Directory(p.join(upgradeCopiesDir(docs).path, 'v5-20261001-120000'))..createSync(recursive: true);
    File(p.join(half.path, dbFileName)).writeAsBytesSync([1]);
    expect(listUpgradeCopies(docs), isEmpty);
    pruneUpgradeCopies(docs);
    expect(half.existsSync(), isFalse);
  });

  test('going back puts the old library back, keeps the pictures, and the current data as the fallback', () async {
    final file = await makeV5(docs);
    final v5Bytes = file.readAsBytesSync();
    final v5Counts = rowCounts(file);
    Directory(p.join(docs.path, 'cards', 'rectified')).createSync(recursive: true);
    File(p.join(docs.path, 'cards', 'rectified', 'abc123.jpg')).writeAsBytesSync([7, 7, 7]);

    final copy = (await copyBeforeUpgrade(docs, targetVersion: 6))!;
    // The upgrade runs, and the owner adds a contact afterwards.
    var db = AppDatabase(NativeDatabase(file));
    await ContactsRepository(db).save(ContactDraft(first: 'Newer', last: 'Contact'));
    await db.close();

    // Go back to it: staged as a restore, swapped in at the next start.
    await stageUpgradeCopyOf(docs, copy);
    expect(await applyPendingRestore(docs), RestoreOutcome.restored);
    expect(file.readAsBytesSync(), v5Bytes);
    expect(rowCounts(file), v5Counts);
    expect(File(p.join(docs.path, 'cards', 'rectified', 'abc123.jpg')).existsSync(), isTrue, reason: 'pictures stay');
    expect(File(p.join(docs.path, 'before_restore', dbFileName)).existsSync(), isTrue, reason: 'current data kept');
    expect(File(p.join(docs.path, 'before_restore', '.keepcards')).existsSync(), isTrue);
    expect(listUpgradeCopies(docs), hasLength(1), reason: 'the copy itself stays');

    // And back again to the newer data: the pictures still stay.
    final backups = Backups(AppDatabase(NativeDatabase.memory()), docs);
    await backups.stageFallback();
    expect(await applyPendingRestore(docs), RestoreOutcome.restored);
    expect(File(p.join(docs.path, 'cards', 'rectified', 'abc123.jpg')).existsSync(), isTrue);
    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final names = await db
        .customSelect('SELECT first FROM people WHERE first = ?', variables: [const Variable('Newer')])
        .get();
    expect(names, hasLength(1));
  });

  test('Delete everything also removes the copies from before an update', () async {
    await makeV5(docs);
    await copyBeforeUpgrade(docs, targetVersion: 6);
    expect(listUpgradeCopies(docs), hasLength(1));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await deleteEverything(db, docs);
    expect(upgradeCopiesDir(docs).existsSync(), isFalse);
  });

  test(
    'a v5 library with orphaned rows (links to rows that no longer exist) still upgrades, and keeps everything',
    () async {
      final file = await makeV5(docs);
      final raw = sq.sqlite3.open(file.path);
      raw.execute('PRAGMA foreign_keys = OFF');
      // What an interrupted purge or merge can leave behind: a card for a person who is gone,
      // a role at a company that is gone, a tag link to a tag that is gone.
      raw.execute(
        "INSERT INTO cards (uuid, person_id, front_sha256, ocr_json, status, scanned_at, created_at, updated_at) VALUES ('orphan-card', 'no-such-person', 'zzz', '{}', 'parsed', 0, 0, 0)",
      );
      raw.execute(
        "INSERT INTO person_tags (uuid, person_id, tag_id, created_at, updated_at) VALUES ('orphan-link', 'no-such-person', 'no-such-tag', 0, 0)",
      );
      raw.close();
      final before = rowCounts(file);
      final db = AppDatabase(NativeDatabase(file));
      final contacts = await ContactsRepository(db).watchContacts(const ContactFilter()).first;
      expect(contacts, hasLength(4));
      await db.close();
      final after = rowCounts(file);
      for (final t in before.keys) {
        expect(after[t], before[t], reason: 'rows in $t');
      }
    },
  );

  test('upgrading a v5 library to the current schema leaves every table with the rows it had', () async {
    final file = await makeV5(docs);
    final before = rowCounts(file);
    expect(before['people'], 4);
    expect(before['cards'], 2);
    expect(before['person_tags'], 1);

    final db = AppDatabase(NativeDatabase(file));
    final contacts = await ContactsRepository(db).watchContacts(const ContactFilter()).first;
    expect(contacts, hasLength(4));
    await db.close();

    final after = rowCounts(file);
    for (final t in before.keys) {
      if (t == 'place_categories') continue; // gains the built-ins' bookkeeping, not rows
      expect(after[t], before[t], reason: 'rows in $t');
    }
    expect(after['place_categories'], before['place_categories']);
  });
}
