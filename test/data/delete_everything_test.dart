import 'dart:io';

import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/contacts/purge.dart';
import 'package:card_organizer/core/data/delete_everything.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/images/image_store.dart';
import 'package:card_organizer/core/settings/settings_repository.dart';
import 'package:card_organizer/core/transfer/backup.dart';
import 'package:card_organizer/features/settings/delete_everything_dialog.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory docs;
  late AppDatabase db;
  late ContactsRepository contacts;
  late ImageStore store;

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('ck_delete');
    db = AppDatabase(NativeDatabase.memory());
    contacts = ContactsRepository(db);
    store = ImageStore(Directory(p.join(docs.path, 'cards')));
  });
  tearDown(() async {
    await db.close();
    await docs.delete(recursive: true);
  });

  Future<int> count(String sql) async => (await db.customSelect(sql).getSingle()).read<int>('n');

  File photo(String name) => File(p.join(docs.path, 'cards', 'rectified', '$name.jpg'))
    ..createSync(recursive: true)
    ..writeAsStringSync(name);

  test('the confirmation word is DELETE however it is capitalised, and nothing else', () {
    expect(isDeleteWord('DELETE'), isTrue);
    expect(isDeleteWord(' delete '), isTrue);
    expect(isDeleteWord('DELET'), isFalse);
    expect(isDeleteWord(''), isFalse);
    expect(isDeleteWord('please delete'), isFalse);
  });

  test('Delete everything removes every contact, photo, backup and fallback copy; settings stay (S15.7)', () async {
    final a = await contacts.save(ContactDraft(first: 'Dana', last: 'Reyes', company: 'Halden', notes: 'Secret'));
    await contacts.save(ContactDraft(first: 'Sam', last: 'Okafor'));
    await db.customStatement('UPDATE people SET logo_sha256 = ? WHERE uuid = ?', ['aaaa', a]);
    photo('aaaa');
    final backups = Backups(db, docs);
    await backups.backupNow();
    Directory(p.join(docs.path, 'before_restore')).createSync();
    File(p.join(docs.path, 'before_restore', 'old.sqlite')).writeAsStringSync('x');
    final settings = SettingsRepository(db);
    await settings.setRegion('GB');
    await settings.setAppLock(true);

    final r = await deleteEverything(db, docs);

    expect(r.people, 2);
    expect(r.files, greaterThanOrEqualTo(3));
    expect(await count('SELECT COUNT(*) AS n FROM people'), 0);
    expect(await count('SELECT COUNT(*) AS n FROM companies'), 0);
    expect(await count('SELECT COUNT(*) AS n FROM roles'), 0);
    expect(await count('SELECT COUNT(*) AS n FROM person_search'), 0);
    expect(Directory(p.join(docs.path, 'cards')).existsSync(), isFalse);
    expect(Directory(p.join(docs.path, 'backups')).existsSync(), isFalse);
    expect(Directory(p.join(docs.path, 'before_restore')).existsSync(), isFalse);
    expect(await settings.appLock(), isTrue, reason: 'settings stay unless asked');
    expect(
      await count('SELECT COUNT(*) AS n FROM place_categories'),
      greaterThan(0),
      reason: 'categories are settings',
    );
    // The app keeps working afterwards.
    await contacts.save(ContactDraft(first: 'New', last: 'Person'));
    expect(await count('SELECT COUNT(*) AS n FROM people'), 1);
  });

  test('Also reset my settings clears the settings table too', () async {
    final settings = SettingsRepository(db);
    await settings.setRegion('GB');
    await settings.setAppLock(true);
    await deleteEverything(db, docs, resetSettings: true);
    expect(await settings.appLock(), isFalse);
    expect(await count('SELECT COUNT(*) AS n FROM app_settings'), 0);
  });

  test(
    'Delete forever now wipes one contact at once and leaves everyone else, and the undo window of others',
    () async {
      final gone = await contacts.save(ContactDraft(first: 'Dana', last: 'Reyes', notes: 'Secret'));
      final kept = await contacts.save(ContactDraft(first: 'Sam', last: 'Okafor'));
      final other = await contacts.save(ContactDraft(first: 'Kim', last: 'Lee', notes: 'Still undoable'));
      for (final (id, h) in [(gone, 'aaaa'), (kept, 'bbbb'), (other, 'cccc')]) {
        await db.customStatement('UPDATE people SET logo_sha256 = ? WHERE uuid = ?', [h, id]);
        photo(h);
      }
      await contacts.delete(other); // deleted a moment ago: still undoable
      await contacts.delete(gone);
      await purgeDeleted(db, before: DateTime.now().add(const Duration(minutes: 1)), store: store, only: {gone});

      final row = await db.customSelect("SELECT display_name, notes FROM people WHERE uuid = '$gone'").getSingle();
      expect(row.read<String>('display_name'), '');
      expect(row.read<String>('notes'), '');
      expect(File(p.join(docs.path, 'cards', 'rectified', 'aaaa.jpg')).existsSync(), isFalse);
      expect(File(p.join(docs.path, 'cards', 'rectified', 'bbbb.jpg')).existsSync(), isTrue);
      final undoable = await db
          .customSelect("SELECT display_name, notes FROM people WHERE uuid = '$other'")
          .getSingle();
      expect(undoable.read<String>('notes'), 'Still undoable', reason: 'someone else\'s undo window is not touched');
    },
  );
}
