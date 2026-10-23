import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:card_organizer/core/career/career_repository.dart';
import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/dupes/duplicates_repository.dart';
import 'package:card_organizer/core/images/image_store.dart';
import 'package:card_organizer/core/tags/tags_repository.dart';
import 'package:card_organizer/core/transfer/backup.dart';
import 'package:card_organizer/core/transfer/csv_import.dart';
import 'package:card_organizer/core/transfer/transfer_repository.dart';
import 'package:card_organizer/core/vcard/vcard_reader.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('CSV', () {
    test('parses quotes, doubled quotes, CRLF, BOM and semicolons', () {
      expect(parseCsv('﻿a,b\r\n"x, y","say ""hi"""\r\n\r\n'), [
        ['a', 'b'],
        ['x, y', 'say "hi"'],
      ]);
      expect(parseCsv('Name;Email\nAnn;a@x.com\n'), [
        ['Name', 'Email'],
        ['Ann', 'a@x.com'],
      ]);
      expect(parseCsv('a,"line1\nline2"\n'), [
        ['a', 'line1\nline2'],
      ]);
    });

    test('guesses Google, Outlook, HubSpot and LinkedIn headers', () {
      expect(
        guessMapping([
          'First Name',
          'Last Name',
          'Company',
          'Job Title',
          'E-mail Address',
          'Mobile Phone',
          'Business Phone',
        ]),
        [
          CsvField.first,
          CsvField.last,
          CsvField.company,
          CsvField.title,
          CsvField.email,
          CsvField.mobile,
          CsvField.phone,
        ],
      );
      expect(guessMapping(['Name', 'Organization 1 - Name', 'Organization 1 - Title', 'E-mail 1 - Value']), [
        CsvField.fullName,
        CsvField.company,
        CsvField.title,
        CsvField.email,
      ]);
      expect(guessMapping(['Company Name', 'Company']), [
        CsvField.company,
        CsvField.skip,
      ], reason: 'one company column');
    });

    test('rows become contacts; full name split; empty rows dropped', () {
      final list = rowsToContacts(
        [
          ['Dana K Reyes', 'Halden', 'd@h.com', '330 555 0142'],
          ['', '', '', ''],
        ],
        [CsvField.fullName, CsvField.company, CsvField.email, CsvField.mobile],
      );
      expect(list.single.first, 'Dana K');
      expect(list.single.last, 'Reyes');
      expect(list.single.phones.single.label, 'Mobile');
    });
  });

  group('import and export', () {
    late AppDatabase db;
    late ContactsRepository contacts;
    late TransferRepository transfer;
    late TagsRepository tags;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      contacts = ContactsRepository(db);
      final dupes = DuplicatesRepository(db, contacts);
      tags = TagsRepository(db, contacts);
      transfer = TransferRepository(db, contacts, dupes, CareerRepository(db, contacts, dupes), tags);
    });
    tearDown(() => db.close());

    test('vCard import: new, merged, skipped, job change; all tagged Imported', () async {
      await contacts.save(
        ContactDraft(first: 'Dana', last: 'Reyes', company: 'Halden Tooling', emails: ['dana@halden.example']),
      );
      await contacts.save(
        ContactDraft(
          first: 'Sam',
          last: 'Okafor',
          company: 'Brightline',
          phones: [const LabeledValue('Mobile', '216 555 0123')],
        ),
      );
      const vcf =
          'BEGIN:VCARD\r\nVERSION:3.0\r\nN:Reyes;Dana;;;\r\nFN:Dana Reyes\r\nORG:Halden Tooling\r\n'
          'EMAIL:dana@halden.example\r\nTEL;TYPE=CELL:330 555 0142\r\nEND:VCARD\r\n' // same company, adds a phone: merged
          'BEGIN:VCARD\r\nVERSION:3.0\r\nN:Reyes;Dana;;;\r\nFN:Dana Reyes\r\nORG:Halden Tooling\r\n'
          'EMAIL:dana@halden.example\r\nEND:VCARD\r\n' // nothing new: skipped
          'BEGIN:VCARD\r\nVERSION:3.0\r\nN:Okafor;Sam;;;\r\nFN:Sam Okafor\r\nORG:Orbit Medical\r\n'
          'TEL;TYPE=CELL:216 555 0123\r\nEND:VCARD\r\n' // same mobile, other company: job change
          'BEGIN:VCARD\r\nVERSION:3.0\r\nN:Bello;Aisha;;;\r\nFN:Aisha Bello\r\nEND:VCARD\r\n'; // new
      final s = await transfer.importContacts(readVCards(vcf));
      expect([s.added, s.merged, s.skipped, s.jobChanges], [2, 1, 1, 1]);
      final all = await contacts.watchContacts(const ContactFilter()).first;
      expect(all.map((c) => c.displayName).toSet(), {'Dana Reyes', 'Sam Okafor', 'Aisha Bello'});
      final imported = (await tags.watchTags().first).single;
      expect(imported.name, 'Imported');
      expect(imported.count, 3, reason: 'merged Dana, new Aisha, new Sam copy');
    });

    test('a match that brings a new note or title is updated, not "already there" (phone test F34)', () async {
      final id = await contacts.save(
        ContactDraft(first: 'Lena', last: 'Hartmann', company: 'Cobalt Fasteners', emails: ['lena@cobalt.example']),
      );
      const vcf =
          'BEGIN:VCARD\r\nVERSION:3.0\r\nN:Hartmann;Lena;;;\r\nFN:Lena Hartmann\r\nORG:Cobalt Fasteners\r\n'
          'TITLE:Purchasing Agent\r\nEMAIL:lena@cobalt.example\r\nNOTE:Met at FabTech\r\nEND:VCARD\r\n';
      final s = await transfer.importContacts(readVCards(vcf));
      expect([s.added, s.merged, s.skipped], [0, 1, 0]);
      final d = (await contacts.loadDetail(id))!;
      expect(d.person.notes, contains('Met at FabTech'));
      expect(d.currentRole?.title, 'Purchasing Agent');
      final again = await transfer.importContacts(readVCards(vcf));
      expect(again.skipped, 1, reason: 'nothing new the second time');
    });

    test('export scopes and formats; images zipped', () async {
      final a = await contacts.save(
        ContactDraft(
          first: 'Dana',
          last: 'Reyes',
          company: 'Halden',
          phones: [const LabeledValue('Office', '440 510 0108', '112')],
          faxes: [const LabeledValue('Fax', '440 510 0202')],
          notes: 'Secret',
        ),
      );
      await contacts.save(ContactDraft(first: 'Sam', last: 'Okafor'));
      final vip = await tags.create('VIP');
      await tags.setTags(a, {vip});

      final v = await transfer.export(ScopeTag(vip), ExportFormat.vcard3, notes: false);
      final text = utf8.decode(v.bytes);
      expect(v.count, 1);
      expect(text, contains('FN:Dana Reyes'));
      expect(text, contains('TEL;TYPE=WORK:+14405100108 x112'));
      expect(text, contains('TEL;TYPE=FAX:+14405100202'));
      expect(text, isNot(contains('Secret')));
      expect(readVCards(text).single.company, 'Halden', reason: 'round-trips');

      final csv = await transfer.export(const ScopeEveryone(), ExportFormat.hubspot);
      expect(csv.bytes.take(3), [0xEF, 0xBB, 0xBF], reason: 'BOM so Excel reads UTF-8');
      expect(utf8.decode(csv.bytes), startsWith('First Name,Last Name'));
      expect(csv.count, 2);
      expect(csv.name, endsWith('.csv'));

      final dir = await Directory.systemTemp.createTemp('ck_exp');
      addTearDown(() => dir.delete(recursive: true));
      final img = File(p.join(dir.path, 'rectified', 'h.jpg'))..createSync(recursive: true);
      img.writeAsBytesSync([1, 2, 3]);
      await contacts.attachCard(a, frontHash: 'h');
      final z = await transfer.export(const ScopePeople([]), ExportFormat.vcard3, images: true, store: ImageStore(dir));
      expect(z.count, 0);
      final zip = await transfer.export(ScopePeople([a]), ExportFormat.vcard3, images: true, store: ImageStore(dir));
      final names = ZipDecoder().decodeBytes(zip.bytes).files.map((f) => f.name).toList();
      expect(names, contains('cards/Dana Reyes (front).jpg'));
      expect(zip.name, endsWith('.zip'));
    });

    test('CSV mappings are remembered per header row', () async {
      final h = ['Who', 'Where'];
      expect(await transfer.savedMapping(h), isNull);
      await transfer.saveMapping(h, [CsvField.fullName, CsvField.company]);
      expect(await transfer.savedMapping(h), [CsvField.fullName, CsvField.company]);
      expect(await transfer.savedMapping(['Who']), isNull);
    });
  });

  test('backup, check, stage and restore round-trip with images', () async {
    final docs = await Directory.systemTemp.createTemp('ck_docs');
    addTearDown(() => docs.delete(recursive: true));
    final dbFile = File(p.join(docs.path, dbFileName));
    var db = AppDatabase(NativeDatabase(dbFile));
    final contacts = ContactsRepository(db);
    final dana = await contacts.save(ContactDraft(first: 'Dana', last: 'Reyes'));
    // Only images a row refers to are backed up.
    await db.customStatement("UPDATE people SET logo_sha256 = 'abc' WHERE uuid = ?", [dana]);
    File(p.join(docs.path, 'cards', 'rectified', 'abc.jpg'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([9, 9, 9]);
    final backups = Backups(db, docs);
    final zip = await backups.create(appVersion: '0.5.0');
    final info = backups.check(zip);
    expect([info.people, info.schema], [1, db.schemaVersion]);

    // Change things after the backup, then restore.
    await contacts.save(ContactDraft(first: 'After', last: 'Backup'));
    File(p.join(docs.path, 'cards', 'rectified', 'abc.jpg')).writeAsBytesSync([0]);
    await backups.stage(zip);
    await db.close();
    expect(await applyPendingRestore(docs), RestoreOutcome.restored);
    expect(await applyPendingRestore(docs), RestoreOutcome.none, reason: 'only once');

    db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(db.close);
    final names = (await ContactsRepository(db).watchContacts(const ContactFilter()).first).map((c) => c.displayName);
    expect(names, ['Dana Reyes']);
    expect(File(p.join(docs.path, 'cards', 'rectified', 'abc.jpg')).readAsBytesSync(), [9, 9, 9]);
    expect(File(p.join(docs.path, 'before_restore', dbFileName)).existsSync(), isTrue, reason: 'fallback kept');
  });

  test('restore refuses damaged, foreign and newer backups', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final b = Backups(db, Directory.systemTemp);
    expect(() => b.check(Uint8List.fromList([1, 2, 3])), throwsA(isA<BackupException>()));
    Uint8List zipOf(Map<String, Object?> manifest, [Map<String, List<int>> files = const {}]) {
      final a = Archive()..add(ArchiveFile.string('manifest.json', jsonEncode(manifest)));
      files.forEach((k, v) => a.add(ArchiveFile.bytes(k, v)));
      return Uint8List.fromList(ZipEncoder().encode(a));
    }

    expect(
      () => b.check(zipOf({'app': 'Other'})),
      throwsA(isA<BackupException>().having((e) => e.message, 'm', contains('not a CardKeep'))),
    );
    expect(
      () => b.check(zipOf({'app': 'CardKeep', 'schema': 99})),
      throwsA(isA<BackupException>().having((e) => e.message, 'm', contains('newer'))),
    );
    expect(
      () => b.check(
        zipOf(
          {
            'app': 'CardKeep',
            'schema': 1,
            'files': {dbFileName: 'deadbeef'},
          },
          {
            dbFileName: [1],
          },
        ),
      ),
      throwsA(isA<BackupException>().having((e) => e.message, 'm', contains('damaged'))),
    );
  });
}
