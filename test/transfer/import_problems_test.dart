import 'package:card_organizer/core/career/career_repository.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/dupes/duplicates_repository.dart';
import 'package:card_organizer/core/tags/tags_repository.dart';
import 'package:card_organizer/core/transfer/csv_import.dart';
import 'package:card_organizer/core/transfer/transfer_repository.dart';
import 'package:card_organizer/core/vcard/vcard.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const map = [CsvField.fullName, CsvField.company, CsvField.email, CsvField.skip];

  test('a spreadsheet row with data but nothing usable is reported by its row number', () {
    final r = csvImport([
      ['Dana Reyes', 'Halden', 'd@h.com', ''], // row 2
      ['', '', '', ''], // row 3: blank, dropped quietly
      ['', '', '', 'only a note column'], // row 4: data, no usable column
      ['Lee Park', '', '', ''], // row 5
    ], map);
    expect(r.contacts.map((c) => c.sourceRow), [2, 5]);
    expect(r.problems.map((p) => p.where), ['Row 4']);
    expect(r.problems.single.reason, contains('no name, company, email or phone'));
  });

  test('rowsToContacts keeps working as before', () {
    expect(
      rowsToContacts([
        ['Dana Reyes', '', '', ''],
      ], map).single.first,
      'Dana',
    );
  });

  group('importing', () {
    late AppDatabase db;
    late TransferRepository transfer;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      final contacts = ContactsRepository(db);
      final dupes = DuplicatesRepository(db, contacts);
      transfer = TransferRepository(
        db,
        contacts,
        dupes,
        CareerRepository(db, contacts, dupes),
        TagsRepository(db, contacts),
      );
    });
    tearDown(() => db.close());

    test('an empty contact is listed with its row, the rest still import', () async {
      final s = await transfer.importContacts(const [
        ExportContact(first: 'Dana', last: 'Reyes', company: 'Halden', sourceRow: 2),
        ExportContact(sourceRow: 3),
        ExportContact(first: 'Lee', last: 'Park', company: 'Acme', sourceRow: 4),
      ]);
      expect(s.added, 2);
      expect(s.problems.map((p) => p.toString()), [startsWith('Row 3: nothing to import')]);
    });

    test('with no row number a vCard contact is named, or numbered', () async {
      final s = await transfer.importContacts(const [ExportContact(), ExportContact(first: 'Ann', last: 'Lee')]);
      expect(s.added, 1);
      expect(s.problems.single.where, 'Contact 1');
    });
  });
}
