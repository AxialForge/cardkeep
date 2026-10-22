import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/parser/ocr.dart';
import 'package:card_organizer/parser/rules.dart';
import 'package:card_organizer/scan/scan_pipeline.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ContactsRepository repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ContactsRepository(db);
  });
  tearDown(() => db.close());

  test('middle name, extension, fax and extras survive save and edit (S10b)', () async {
    final id = await repo.save(
      ContactDraft(
        first: 'Dana',
        middle: 'K.',
        last: 'Reyes',
        phones: [const LabeledValue('Office', '(440) 510-0108', '112')],
        faxes: [const LabeledValue('Fax', '440 510 0202')],
        extras: [const LabeledValue('Licence', 'Lic. # 48213'), const LabeledValue('Hours', '')],
      ),
    );
    final d = (await repo.loadDetail(id))!;
    expect(d.person.displayName, 'Dana K. Reyes');
    expect(d.active(ContactKind.office).single.extension, '112');
    expect(d.active(ContactKind.fax).single.value, '+14405100202');
    expect(d.callTarget!.value, '+14405100108', reason: 'fax is never the call target');
    expect(d.extras.map((e) => e.label), ['Licence'], reason: 'empty extras dropped');

    final draft = d.toDraft();
    expect(draft.middle, 'K.');
    expect(draft.phones.single.ext, '112');
    expect(draft.faxes.single.value, '+14405100202');

    // Change only the extension: the same row is updated.
    draft.phones = [LabeledValue('Office', draft.phones.single.value, '115')];
    await repo.save(draft, id: id);
    final d2 = (await repo.loadDetail(id))!;
    expect(d2.active(ContactKind.office).single.extension, '115');
    expect(d2.active(ContactKind.office).single.id, d.active(ContactKind.office).single.id);
    expect((await repo.watchContacts(const ContactFilter(query: '48213')).first).single.id, id);
  });

  test('a scanned capitals card becomes a tidy draft', () {
    final c = parseCard(
      OcrPage.fromText(
        ['ENPRESS LLC', 'FRED J. PANETO', 'Tel. (440) 510-0108 Ext. 112', 'Fax (440) 510-0202', 'Since 1985'],
        heights: [14, 20, 9, 9, 8],
      ),
    );
    final d = draftFromScan(c);
    expect([d.first, d.middle, d.last], ['Fred', 'J.', 'Paneto']);
    expect(d.phones.single.ext, '112');
    expect(d.faxes.single.value, '+14405100202');
    expect(d.extras.single.label, 'Since');
  });
}
