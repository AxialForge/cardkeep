import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/dupes/duplicates_repository.dart';
import 'package:card_organizer/core/dupes/matcher.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ContactsRepository contacts;
  late DuplicatesRepository dupes;
  final clock = DateTime(2026, 10, 20, 9);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    contacts = ContactsRepository(db, clock: () => clock);
    dupes = DuplicatesRepository(db, contacts, clock: () => clock);
  });
  tearDown(() => db.close());

  Future<String> person(
    String first,
    String company, {
    List<String> mobiles = const [],
    List<String> emails = const [],
    String notes = '',
  }) => contacts.save(
    ContactDraft(
      first: first,
      last: 'Reyes',
      title: 'Buyer',
      company: company,
      phones: [for (final m in mobiles) LabeledValue('Mobile', m)],
      emails: emails,
      notes: notes,
    ),
  );

  Future<int> count(String sql) async => (await db.customSelect(sql).getSingle()).read<int>('n');

  test('scanAll finds the pair; dismiss hides it for good', () async {
    final a = await person('Dana', 'Halden Tooling', mobiles: ['330 555 0142']);
    final b = await person('Dana', 'Halden Tooling Inc', emails: ['dana@halden.example']);
    await person('Sam', 'Brightline');
    final pairs = await dupes.scanAll();
    expect(pairs, hasLength(1));
    expect(pairs.single.match.reason, MatchReason.nameCompany);
    expect((await dupes.matchesFor(a)).single.b.id, b);
    await dupes.dismiss(b, a);
    expect(await dupes.scanAll(), isEmpty);
    expect(await dupes.matchesFor(a), isEmpty);
  });

  test('merge repoints every table, unions points, tombstones the loser; undo restores all', () async {
    final keep = await person(
      'Dana',
      'Halden Tooling',
      mobiles: ['330 555 0142'],
      emails: ['dana@halden.example'],
      notes: 'Met at FabTech',
    );
    final lose = await person(
      'Dana',
      'Halden Tooling',
      mobiles: ['330 555 0142', '330 555 0999'],
      emails: ['d.reyes@halden.example'],
      notes: 'Wants a quote',
    );
    final other = await person('Sam', 'Brightline');

    // One row in every table that points at a person.
    final tag = await db.into(db.tags).insertReturning(TagsCompanion.insert(name: 'VIP'));
    final tag2 = await db.into(db.tags).insertReturning(TagsCompanion.insert(name: 'Expo'));
    await db.into(db.personTags).insert(PersonTagsCompanion.insert(personId: keep, tagId: tag.uuid));
    await db.into(db.personTags).insert(PersonTagsCompanion.insert(personId: lose, tagId: tag.uuid)); // repeat
    await db.into(db.personTags).insert(PersonTagsCompanion.insert(personId: lose, tagId: tag2.uuid));
    await contacts.attachCard(lose, frontHash: 'h1');
    await db
        .into(db.changeSuggestions)
        .insert(
          ChangeSuggestionsCompanion.insert(personId: lose, kind: SuggestionKind.moved, source: SuggestionSource.scan),
        );
    await db
        .into(db.successions)
        .insert(SuccessionsCompanion.insert(predecessorPersonId: lose, successorPersonId: Value(other)));
    await db
        .into(db.successions)
        .insert(SuccessionsCompanion.insert(predecessorPersonId: other, successorPersonId: Value(lose)));
    await (db.update(
      db.people,
    )..where((p) => p.uuid.equals(other))).write(PeopleCompanion(introducedByPersonId: Value(lose)));

    final undo = await dupes.merge(keep, lose, const MergeChoices());

    for (final t in ['roles', 'contact_points', 'cards', 'change_suggestions', 'person_tags']) {
      expect(
        await count("SELECT COUNT(*) AS n FROM $t WHERE person_id = '$lose' AND deleted_at IS NULL"),
        0,
        reason: t,
      );
    }
    expect(
      await count(
        "SELECT COUNT(*) AS n FROM successions WHERE '$lose' IN (predecessor_person_id, successor_person_id)",
      ),
      0,
    );
    expect(await count("SELECT COUNT(*) AS n FROM people WHERE introduced_by_person_id = '$lose'"), 0);

    final d = (await contacts.loadDetail(keep))!;
    expect(d.active(ContactKind.mobile).map((p) => p.value), unorderedEquals(['+13305550142', '+13305550999']));
    expect(
      d.active(ContactKind.email).map((p) => p.value),
      unorderedEquals(['dana@halden.example', 'd.reyes@halden.example']),
    );
    expect(d.emailTarget!.value, 'dana@halden.example'); // keeper's primary kept
    expect(d.roles.where((r) => r.status == RoleStatus.current), hasLength(1));
    expect(d.cards, hasLength(1));
    expect(d.person.notes, 'Met at FabTech\nWants a quote');
    expect(await count("SELECT COUNT(*) AS n FROM person_tags WHERE person_id = '$keep' AND deleted_at IS NULL"), 2);
    expect(await contacts.loadDetail(lose), isNull);
    expect((await contacts.watchContacts(const ContactFilter(query: 'Dana')).first).map((c) => c.id), [keep]);

    await dupes.undo(undo);

    final k = (await contacts.loadDetail(keep))!, l = (await contacts.loadDetail(lose))!;
    expect(k.person.notes, 'Met at FabTech');
    expect(k.active(ContactKind.mobile).map((p) => p.value), ['+13305550142']);
    expect(l.active(ContactKind.mobile).map((p) => p.value), unorderedEquals(['+13305550142', '+13305550999']));
    expect(l.active(ContactKind.email).single.isPrimary, isTrue);
    expect(l.currentRole!.company, 'Halden Tooling');
    expect(l.cards, hasLength(1));
    expect(await count("SELECT COUNT(*) AS n FROM person_tags WHERE person_id = '$lose' AND deleted_at IS NULL"), 2);
    expect(
      await count(
        "SELECT COUNT(*) AS n FROM successions WHERE '$lose' IN (predecessor_person_id, successor_person_id)",
      ),
      2,
    );
    expect(await count("SELECT COUNT(*) AS n FROM people WHERE introduced_by_person_id = '$lose'"), 1);
    expect(await count("SELECT COUNT(*) AS n FROM change_suggestions WHERE person_id = '$lose'"), 1);
    expect((await contacts.watchContacts(const ContactFilter(query: 'Dana')).first), hasLength(2));
  });

  test('picking the other record\'s name and role; a different company is kept as history', () async {
    final keep = await person('Dana', 'Halden Tooling', mobiles: ['330 555 0142']);
    final lose = await person('Danielle', 'Brightline', mobiles: ['330 555 0142']);
    await dupes.merge(keep, lose, const MergeChoices(name: Side.lose, role: Side.lose));
    final d = (await contacts.loadDetail(keep))!;
    expect(d.person.first, 'Danielle');
    expect(d.currentRole!.company, 'Brightline');
    expect(d.roles.where((r) => r.status == RoleStatus.former).single.company, 'Halden Tooling');
  });
}
