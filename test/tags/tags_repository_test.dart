import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/tags/tags_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ContactsRepository contacts;
  late TagsRepository tags;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    contacts = ContactsRepository(db);
    tags = TagsRepository(db, contacts);
  });
  tearDown(() => db.close());

  Future<String> person(String first) => contacts.save(ContactDraft(first: first, last: 'Test'));
  Future<List<String>> names(ContactFilter f) async => [for (final c in await contacts.watchContacts(f).first) c.first];

  test('create, assign, count, filter and search by tag', () async {
    final a = await person('Ann'), b = await person('Ben');
    await person('Cal');
    final vip = await tags.create('VIP');
    expect(await tags.create(' vip '), vip, reason: 'same name, any case');
    final expo = await tags.create('FabTech 2026');

    await tags.setTags(a, {vip, expo});
    await tags.addToAll([a, b], vip);

    final all = await tags.watchTags().first;
    expect({for (final t in all) t.name: t.count}, {'FabTech 2026': 1, 'VIP': 2});
    expect([for (final t in await tags.watchTagsOf(a).first) t.name], ['FabTech 2026', 'VIP']);
    expect(await names(ContactFilter(tagId: vip)), ['Ann', 'Ben']);
    expect(await names(const ContactFilter(query: 'fabtech')), ['Ann']);

    await tags.setTags(a, {expo}); // remove VIP
    expect(await names(ContactFilter(tagId: vip)), ['Ben']);
    await tags.setTags(a, {expo, vip}); // re-add revives the row
    expect(await names(ContactFilter(tagId: vip)), ['Ann', 'Ben']);
  });

  test('rename updates search; delete removes the tag from everyone', () async {
    final a = await person('Ann');
    final t = await tags.create('Lead');
    await tags.setTags(a, {t});
    await tags.rename(t, 'Hot prospect');
    expect(await names(const ContactFilter(query: 'prospect')), ['Ann']);
    await tags.recolor(t, tagColors[3]);
    expect((await tags.watchTags().first).single.color, tagColors[3]);

    await tags.delete(t);
    expect(await tags.watchTags().first, isEmpty);
    expect(await tags.watchTagsOf(a).first, isEmpty);
    expect(await names(const ContactFilter(query: 'prospect')), isEmpty);
    expect(await names(const ContactFilter()), ['Ann'], reason: 'people stay');
  });

  test('system tags are created once and survive a rename', () async {
    final id = await tags.ensureSystem(SystemTag.imported);
    await tags.rename(id, 'From my old phone');
    expect(await tags.ensureSystem(SystemTag.imported), id);
    await tags.delete(id);
    final again = await tags.ensureSystem(SystemTag.imported);
    expect(again, isNot(id));
    expect((await tags.watchTags().first).single.name, 'Imported');
  });
}
