import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/contacts/place_category_repository.dart';
import 'package:card_organizer/core/csv/csv_export.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/vcard/vcard.dart';
import 'package:card_organizer/core/vcard/vcard_reader.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Customizable place categories (S14b.6).
void main() {
  late AppDatabase db;
  late ContactsRepository contacts;
  late PlaceCategoryRepository cats;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    contacts = ContactsRepository(db);
    cats = PlaceCategoryRepository(db, reindex: contacts.reindex);
  });
  tearDown(() => db.close());

  Future<String> place(String name, String category) =>
      contacts.save(ContactDraft(kind: PersonKind.place, company: name, category: category));

  test('a new database has the five built-in categories, Other last', () async {
    final all = await cats.all();
    expect(all.map((c) => c.label), ['Store', 'Restaurant', 'Vendor', 'Service', 'Other']);
    expect(all.last.canDelete, isFalse);
  });

  test('add, rename, reorder; a rename shows in the list and in search', () async {
    final id = await cats.add('Machine shop');
    expect(await cats.add('machine SHOP'), id, reason: 'same name, same category');
    await place('Precision Gear Works', id);

    await cats.rename(id, 'Machining');
    final list = await contacts.watchContacts(const ContactFilter()).first;
    expect(list.single.subtitle, 'Machining');
    final found = await contacts.watchContacts(const ContactFilter(query: 'machining')).first;
    expect(found.map((c) => c.displayName), ['Precision Gear Works']);

    await cats.reorder([id, 'store', 'restaurant', 'vendor', 'service', 'other']);
    final all = await cats.all();
    expect(all.first.label, 'Machining');
    expect(all.last.id, 'other');
  });

  test('deleting a category moves its places to Other; Other cannot be deleted', () async {
    final id = await cats.add('Print shop');
    await place('Copy Corner', id);
    await place('Lakeside Hardware', 'store');
    expect(await cats.placeCount(id), 1);

    await cats.delete(id);
    final list = await contacts.watchContacts(const ContactFilter(placesOnly: true)).first;
    final byName = {for (final c in list) c.displayName: c};
    expect(byName['Copy Corner']!.category, 'other');
    expect(byName['Copy Corner']!.subtitle, 'Other');
    expect(byName['Lakeside Hardware']!.category, 'store');
    expect((await cats.all()).map((c) => c.id), isNot(contains(id)));

    await cats.delete('other');
    expect((await cats.all()).map((c) => c.id), contains('other'));
  });

  test('export writes the category label; import finds or adds it by name', () async {
    final id = await cats.add('Machine shop');
    final pid = await place('Precision Gear Works', id);
    final c = contacts.toExport((await contacts.loadDetail(pid))!);
    expect(c.category, 'Machine shop');
    expect(writeVCard(c), contains('X-CARDKEEP-CATEGORY:Machine shop'));
    final csv = writeCsv([c]).split('\r\n');
    expect(csv.first.split(',').last, 'Category');
    expect(csv.last.split(',').last, 'Machine shop');

    final back = readVCards(writeVCard(c, version: '4.0')).single;
    expect(back.isOrg, isTrue);
    expect(back.category, 'Machine shop');
    expect(await cats.idForLabel('machine shop'), id);
  });
}
