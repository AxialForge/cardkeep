import 'dart:io';

import 'package:archive/archive.dart';
import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/contacts/purge.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/images/image_store.dart';
import 'package:card_organizer/core/transfer/backup.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory docs;
  late AppDatabase db;
  late ContactsRepository contacts;
  late ImageStore store;

  File logo(String hash) => File(p.join(docs.path, 'cards', 'logo', '$hash.png'));

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('ck_purge');
    db = AppDatabase(NativeDatabase.memory());
    contacts = ContactsRepository(db);
    store = ImageStore(Directory(p.join(docs.path, 'cards')));
  });
  tearDown(() async {
    await db.close();
    await docs.delete(recursive: true);
  });

  Future<(String, String)> twoPeople() async {
    final gone = await contacts.save(ContactDraft(first: 'Dana', last: 'Reyes', notes: 'Secret'));
    final kept = await contacts.save(ContactDraft(first: 'Sam', last: 'Okafor'));
    for (final (id, h) in [(gone, 'aaaa'), (kept, 'bbbb')]) {
      await db.customStatement('UPDATE people SET logo_sha256 = ? WHERE uuid = ?', [h, id]);
      logo(h)
        ..createSync(recursive: true)
        ..writeAsStringSync(h);
    }
    await contacts.delete(gone);
    return (gone, kept);
  }

  test('a deleted contact is wiped after the retention period, with its images (MOB-PRV-0002)', () async {
    final (gone, _) = await twoPeople();
    final now = DateTime.now();
    expect((await purgeDeleted(db, before: now.subtract(retention), store: store)).people, 0, reason: 'undo window');
    expect(logo('aaaa').existsSync(), isTrue);

    final r = await purgeDeleted(db, before: now.add(const Duration(minutes: 1)), store: store);
    expect(r.people, 1);
    final row = await db.customSelect('SELECT * FROM people WHERE uuid = ?', variables: [Variable(gone)]).getSingle();
    expect(row.read<String>('display_name'), '');
    expect(row.read<String>('notes'), '');
    expect(row.readNullable<String>('logo_sha256'), isNull);
    expect(logo('aaaa').existsSync(), isFalse);
    expect(logo('bbbb').existsSync(), isTrue, reason: 'other contacts untouched');
  });

  test('a backup carries no deleted contacts and none of their images', () async {
    await twoPeople();
    final zip = ZipDecoder().decodeBytes(await Backups(db, docs).create());
    final names = zip.files.map((f) => f.name).toSet();
    expect(names, contains('cards/logo/bbbb.png'));
    expect(names, isNot(contains('cards/logo/aaaa.png')));
    final dbBytes = zip.findFile(dbFileName)!.content;
    expect(String.fromCharCodes(dbBytes).contains('Secret'), isFalse);
    expect(logo('aaaa').existsSync(), isTrue, reason: 'the live data keeps its undo window');
  });
}
