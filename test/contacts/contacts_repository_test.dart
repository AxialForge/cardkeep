import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/text/normalize.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

ContactDraft priya() => ContactDraft(
  first: 'Priya',
  last: 'Nambiar',
  title: 'Director of Procurement',
  company: 'Halden Tooling Group',
  phones: [const LabeledValue('Mobile', '(330) 555-0142'), const LabeledValue('Office', '330 555 0188')],
  emails: ['P.Nambiar@HaldenTooling.example'],
  website: 'haldentooling.example',
  leadRating: LeadRating.warm,
);

void main() {
  late AppDatabase db;
  late ContactsRepository repo;
  var clock = DateTime(2026, 10, 19, 9);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ContactsRepository(db, clock: () => clock);
  });
  tearDown(() => db.close());

  Future<List<ContactSummary>> list([ContactFilter f = const ContactFilter()]) => repo.watchContacts(f).first;

  test('save creates person, company, role and normalised contact points', () async {
    final id = await repo.save(priya());
    final d = (await repo.loadDetail(id))!;
    expect(d.person.displayName, 'Priya Nambiar');
    expect(d.currentRole!.title, 'Director of Procurement');
    expect(d.currentRole!.company, 'Halden Tooling Group');
    expect(d.callTarget!.value, '+13305550142');
    expect(d.active(ContactKind.office).single.value, '+13305550188');
    expect(d.emailTarget!.value, 'p.nambiar@haldentooling.example');
    expect(d.emailTarget!.isPrimary, isTrue);

    final rows = await list();
    expect(rows.single.subtitle, 'Director of Procurement · Halden Tooling Group');
    expect(rows.single.initials, 'PN');
  });

  test('companies are shared by normalised name', () async {
    await repo.save(priya());
    await repo.save(ContactDraft(first: 'Sam', last: 'Ode', company: 'HALDEN TOOLING GROUP, INC.'));
    final companies = await db.select(db.companies).get();
    expect(companies, hasLength(1));
    expect((await repo.watchStats().first).companies, 1);
  });

  test('editing keeps unchanged contact points and tombstones removed ones', () async {
    final id = await repo.save(priya());
    final before = (await repo.loadDetail(id))!;
    final mobileId = before.callTarget!.id;

    final d = before.toDraft()..phones.removeWhere((p) => p.label == 'Office');
    clock = clock.add(const Duration(minutes: 5));
    await repo.save(d, id: id);

    final after = (await repo.loadDetail(id))!;
    expect(after.callTarget!.id, mobileId, reason: 'unchanged row keeps its uuid for sync');
    expect(after.active(ContactKind.office), isEmpty);
    final tomb = await (db.select(db.contactPoints)..where((c) => c.deletedAt.isNotNull())).get();
    expect(tomb.single.value, '+13305550188');
    expect(after.person.updatedAt, clock);
  });

  test('former contact points are kept and never used as default targets', () async {
    final id = await repo.save(priya());
    final mobile = (await repo.loadDetail(id))!.callTarget!;
    await (db.update(
      db.contactPoints,
    )..where((c) => c.uuid.equals(mobile.id))).write(const ContactPointsCompanion(status: Value(ContactStatus.former)));
    final d = (await repo.loadDetail(id))!;
    expect(d.callTarget!.value, '+13305550188', reason: 'falls back to office');
    expect(d.textTarget, isNull);
    expect(d.points.where((p) => p.status == ContactStatus.former), hasLength(1));
  });

  test('search by name prefix, company, email, phone digits and notes', () async {
    final id = await repo.save(priya());
    await repo.save(ContactDraft(first: 'Marcus', last: 'Oyelaran', company: 'Calder Hydraulics'));
    await repo.addNote(id, 'Wants die insert pricing');

    Future<List<String>> q(String s) async => [for (final r in await list(ContactFilter(query: s))) r.displayName];
    expect(await q('pri'), ['Priya Nambiar']);
    expect(await q('calder'), ['Marcus Oyelaran']);
    expect(await q('haldentooling'), ['Priya Nambiar']);
    expect(await q('555-0142'), ['Priya Nambiar']);
    expect(await q('3305550188'), ['Priya Nambiar']);
    expect(await q('insert'), ['Priya Nambiar']);
    expect(await q('nobody'), isEmpty);
  });

  test('sorting and filters', () async {
    await repo.save(ContactDraft(first: 'Zed', last: 'Abbot', company: 'Zeta Co'));
    clock = clock.add(const Duration(hours: 1));
    await repo.save(ContactDraft(first: 'Amy', last: 'Young', company: 'Acme', leadRating: LeadRating.hot));

    expect([for (final r in await list()) r.last], ['Abbot', 'Young']);
    expect([for (final r in await list(const ContactFilter(sort: ContactSort.company))) r.last], ['Young', 'Abbot']);
    expect([for (final r in await list(const ContactFilter(sort: ContactSort.recent))) r.last], ['Young', 'Abbot']);
    expect([for (final r in await list(const ContactFilter(rating: LeadRating.hot))) r.last], ['Young']);
  });

  test('delete tombstones and hides; restore brings it back searchable', () async {
    final id = await repo.save(priya());
    await repo.delete(id);
    expect(await list(), isEmpty);
    expect(await list(const ContactFilter(query: 'priya')), isEmpty);
    expect((await db.select(db.people).get()).single.deletedAt, isNotNull);

    await repo.restore(id);
    expect(await list(const ContactFilter(query: 'priya')), hasLength(1));
  });

  test('follow-ups count this week and moving the date reopens a done follow-up', () async {
    final id = await repo.save(priya()..followupAt = clock.add(const Duration(days: 3)));
    expect((await repo.watchStats().first).followupsThisWeek, 1);
    await repo.markFollowupDone(id);
    expect((await repo.watchStats().first).followupsThisWeek, 0);

    final d = (await repo.loadDetail(id))!.toDraft()..followupAt = clock.add(const Duration(days: 5));
    await repo.save(d, id: id);
    expect((await repo.loadDetail(id))!.person.followupDoneAt, isNull);
  });

  test('notes log adds dated lines on top', () async {
    final id = await repo.save(priya());
    await repo.addNote(id, 'First call');
    clock = DateTime(2026, 10, 20);
    await repo.addNote(id, 'Sent quote');
    expect((await repo.loadDetail(id))!.person.notes, '2026-10-20  Sent quote\n2026-10-19  First call');
  });

  test('vCard export uses active points only', () async {
    final id = await repo.save(priya());
    final e = repo.toExport((await repo.loadDetail(id))!);
    expect(e.company, 'Halden Tooling Group');
    expect(e.phones.map((p) => p.number), ['+13305550142', '+13305550188']);
  });

  test('helpers', () {
    expect(companyKey('Halden Tooling Group, Inc.'), 'halden tooling');
    expect(companyKey('Halden Tooling'), 'halden tooling');
    expect(ftsQuery('  '), isNull);
    expect(ftsQuery('Pri Nam'), '"pri"* "nam"*');
    expect(ftsQuery('(330) 555'), '"330"* "555"*');
    expect(formatPhone('+13305550142'), startsWith('+1 '));
    expect(normalizePhone('not a number', 'US'), 'not a number');
  });
}
