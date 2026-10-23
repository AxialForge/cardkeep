import 'package:card_organizer/core/contacts/company_repository.dart';
import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/dupes/duplicates_repository.dart';
import 'package:card_organizer/core/dupes/matcher.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// S14d: bulk merge and company pages.
void main() {
  late AppDatabase db;
  late ContactsRepository contacts;
  late DuplicatesRepository dupes;
  var clock = DateTime(2026, 10, 23, 9);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    contacts = ContactsRepository(db, clock: () => clock);
    dupes = DuplicatesRepository(db, contacts, clock: () => clock);
  });
  tearDown(() => db.close());

  Future<String> person(
    String first,
    String last,
    String company, {
    List<String> mobiles = const [],
    List<String> emails = const [],
    String notes = '',
    String title = 'HR Manager',
  }) {
    clock = clock.add(const Duration(minutes: 1));
    return contacts.save(
      ContactDraft(
        first: first,
        last: last,
        title: title,
        company: company,
        phones: [for (final m in mobiles) LabeledValue('Mobile', m)],
        emails: emails,
        notes: notes,
      ),
    );
  }

  Future<int> live() async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM people WHERE deleted_at IS NULL').getSingle()).read<int>('n');

  test('four copies of one card are one group; a name-and-company-only match is not obvious', () async {
    for (var i = 0; i < 4; i++) {
      await person('Bridgette', 'Kipling', 'Enpress LLC', emails: ['bkipling@enpress.example'], notes: 'copy $i');
    }
    await person('Veronica', 'Vecchio', 'Pyrotek', mobiles: ['330 555 0101']);
    await person('Veronica', 'Vecchio', 'Pyrotek', mobiles: ['330 555 0101']);
    // Same name and company but nothing shared: left for the owner to look at.
    await person('Dana', 'Reyes', 'Halden Tooling', emails: ['dana@halden.example']);
    await person('Dana', 'Reyes', 'Halden Tooling', emails: ['d.reyes@other.example']);

    final pairs = await dupes.scanAll();
    final groups = obviousGroups(pairs);
    expect(groups.map((g) => g.length).toList()..sort(), [2, 4]);
    final plan = await dupes.bulkPlan(pairs);
    expect(plan, hasLength(2));
    expect(plan.map((g) => g.keeper.name), ['Bridgette Kipling', 'Veronica Vecchio']);
  });

  test('merge all lands in one go and one Undo restores every contact', () async {
    final ids = [
      for (var i = 0; i < 3; i++)
        await person('Bridgette', 'Kipling', 'Enpress LLC', emails: ['bkipling@enpress.example'], notes: 'copy $i'),
    ];
    await person('Sam', 'Ellery', 'Orbit Studio', emails: ['sam@orbit.example']);
    expect(await live(), 4);

    final plan = await dupes.bulkPlan();
    expect(plan.single.keeper.id, ids.last, reason: 'newest record is kept');
    final undo = await dupes.mergeAll(plan);
    expect(undo.count, 2);
    expect(await live(), 2);
    final kept = (await contacts.loadDetail(ids.last))!;
    expect(kept.person.notes.split('\n').toSet(), {'copy 0', 'copy 1', 'copy 2'}, reason: 'notes joined');
    expect(await dupes.scanAll(), isEmpty);

    await dupes.undoAll(undo);
    expect(await live(), 4);
    for (final id in ids) {
      expect((await contacts.loadDetail(id))!.person.notes, startsWith('copy '));
    }
    expect((await contacts.loadDetail(ids.last))!.person.notes, 'copy 2');
  });

  test('undo restores copies at differently spelled companies, with their roles (phone test)', () async {
    final ids = [
      await person('Bridgette', 'Kipling', 'ENPRESS LLC', emails: ['b@enpress.example']),
      await person('Bridgette', 'Kipling', 'ENPRESS LLC', emails: ['b@enpress.example']),
      await person('Bridgette', 'Kipling', 'ENPRESS LIC', emails: ['b@enpress.example']),
      await person('Bridgette', 'Kipling', 'ENPRESS LIC', emails: ['b@enpress.example']),
    ];
    final plan = await dupes.bulkPlan();
    expect(plan.single.others, hasLength(3));
    expect(plan.single.company, 'ENPRESS LLC', reason: 'the newest copy says LIC, but LLC has a legal suffix');
    final undo = await dupes.mergeAll(plan);
    expect(await live(), 1);
    final merged = (await contacts.loadDetail(plan.single.keeper.id))!;
    expect(merged.roles.where((r) => r.status == RoleStatus.current).single.company, 'ENPRESS LLC');
    await dupes.undoAll(undo);
    expect(await live(), 4);
    for (final id in ids) {
      final d = (await contacts.loadDetail(id))!;
      expect(d.roles.where((r) => r.status == RoleStatus.current), hasLength(1), reason: id);
      expect(d.points, isNotEmpty, reason: id);
    }
  });

  test('a slogan is never the kept company; the majority title wins a tie', () {
    MatchCandidate c(String id, String company, [String email = 'f@acme.example']) =>
        MatchCandidate(id: id, name: 'Fritz Hoffmann', company: company, emails: {email});
    final slogan = c('a', 'Proudly Serving the Aerospace Industry');
    final real = c('b', 'Acme Aero');
    expect(pickRole([slogan, real]).id, 'b');
    // Same company everywhere: the title most copies share decides.
    final x = c('x', 'Acme Aero'), y = c('y', 'Acme Aero'), z = c('z', 'Acme Aero');
    expect(pickRole([x, y, z], titles: {'x': 'Buyr', 'y': 'Buyer', 'z': 'Buyer'}).id, 'y');
  });

  test('a place is never merged with a person, even with the same name and phone', () async {
    await person('Lakeside', 'Hardware', 'Lakeside Hardware', mobiles: ['440 555 0161']);
    clock = clock.add(const Duration(minutes: 1));
    await contacts.save(
      ContactDraft(
        company: 'Lakeside Hardware',
        kind: PersonKind.place,
        phones: [const LabeledValue('Mobile', '440 555 0161')],
      ),
    );
    expect(obviousGroups(await dupes.scanAll()), isEmpty);
    expect(await dupes.bulkPlan(), isEmpty);
  });

  test('company page lists current, former and places, events, shared phones and the last card', () async {
    final a = await person('Avery', 'Lindqvist', 'Northwind Forging', emails: ['avery@northwind.example']);
    final b = await person('Theo', 'Vance', 'Northwind Forging', title: 'Senior Buyer');
    await person('Sam', 'Ellery', 'Orbit Studio');
    final cid = (await contacts.loadDetail(a))!.roles.single.companyId!;
    expect((await contacts.loadDetail(b))!.roles.single.companyId, cid, reason: 'one company row');

    // A shared office number on both people is the company's.
    for (final id in [a, b]) {
      await db
          .into(db.contactPoints)
          .insert(ContactPointsCompanion.insert(personId: id, kind: ContactKind.office, value: '+13305550100'));
    }
    // Theo leaves: his role becomes former.
    await db.customStatement("UPDATE roles SET status = 'former' WHERE person_id = ?", [b]);

    final c = (await CompanyRepository(db).load(cid))!;
    expect(c.name, 'Northwind Forging');
    expect(c.current.map((p) => p.displayName), ['Avery Lindqvist']);
    expect(c.former.map((p) => p.displayName), ['Theo Vance']);
    expect(c.places, isEmpty);
    expect(c.sharedPhones, ['+13305550100']);
    expect(c.lastContact, isNotNull);
    expect(await CompanyRepository(db).load('nope'), isNull);
  });
}
