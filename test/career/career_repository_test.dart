import 'package:card_organizer/core/career/career_repository.dart';
import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/dupes/duplicates_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ContactsRepository contacts;
  late DuplicatesRepository dupes;
  late CareerRepository career;
  final clock = DateTime(2026, 11, 1, 9);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    contacts = ContactsRepository(db, clock: () => clock);
    dupes = DuplicatesRepository(db, contacts, clock: () => clock);
    career = CareerRepository(db, contacts, dupes, clock: () => clock);
  });
  tearDown(() => db.close());

  Future<String> dana({
    String company = 'Halden Tooling',
    String email = 'dana@halden.example',
    String mobile = '330 555 0142',
  }) => contacts.save(
    ContactDraft(
      first: 'Dana',
      last: 'Reyes',
      title: 'Buyer',
      company: company,
      phones: [LabeledValue('Mobile', mobile)],
      emails: [email],
    ),
  );

  Future<(String, CareerSuggestion)> scanAtNewJob() async {
    final old = await dana();
    final fresh = await dana(company: 'Brightline', email: 'dana@brightline.example');
    await career.suggestMove(old, newPersonId: fresh, company: 'Brightline', title: 'Buyer');
    final s = (await career.watchPending().first).single;
    return (old, s);
  }

  test('keep history: new current role, old role former, old email former, status moved', () async {
    final (old, s) = await scanAtNewJob();
    expect(s.newPersonId, isNotNull);
    await career.resolveMove(s, JobChange.keepHistory);
    final d = (await contacts.loadDetail(old))!;
    expect(d.currentRole!.company, 'Brightline');
    expect(d.roles.where((r) => r.status == RoleStatus.former).single.company, 'Halden Tooling');
    expect(d.emailTarget!.value, 'dana@brightline.example');
    expect(d.points.firstWhere((p) => p.value == 'dana@halden.example').status, ContactStatus.former);
    expect(d.person.status, PersonStatus.moved);
    expect(await contacts.loadDetail(s.newPersonId!), isNull, reason: 'the new card merged in');
    expect(await career.watchPending().first, isEmpty);
  });

  test('replace: old role and old work email removed, status active', () async {
    final (old, s) = await scanAtNewJob();
    await career.resolveMove(s, JobChange.replace);
    final d = (await contacts.loadDetail(old))!;
    expect(d.roles.map((r) => r.company), ['Brightline']);
    expect(d.points.where((p) => p.kind == ContactKind.email).map((p) => p.value), ['dana@brightline.example']);
    expect(d.person.status, PersonStatus.active);
  });

  test('different person: nothing changes, pair never suggested again', () async {
    final (old, s) = await scanAtNewJob();
    await career.resolveMove(s, JobChange.different);
    expect((await contacts.loadDetail(old))!.currentRole!.company, 'Halden Tooling');
    expect(await contacts.loadDetail(s.newPersonId!), isNotNull);
    expect(await career.watchPending().first, isEmpty);
    expect(await dupes.matchesFor(old), isEmpty, reason: 'remembered as not a duplicate');
  });

  test('manual move with a successor at the old company, and the follow-up moves', () async {
    final old = await dana();
    final sam = await contacts.save(ContactDraft(first: 'Sam', last: 'Okafor', company: 'Halden Tooling'));
    await contacts.setFollowup(old, DateTime(2026, 11, 20, 8));
    await career.changeJob(old, company: 'Orbit Medical', title: 'Supply Chain Lead');
    await career.addSuccession(old, sam, roleTitle: 'Buyer');
    await career.moveFollowup(old, sam);

    final d = (await contacts.loadDetail(old))!;
    expect(d.currentRole!.company, 'Orbit Medical');
    expect(d.person.followupAt, isNull);
    expect((await contacts.loadDetail(sam))!.person.followupAt, DateTime(2026, 11, 20, 8));
    final v = await career.succession(old);
    expect(v.replacedBy!.name, 'Sam Okafor');
    expect(v.replacedByRole, 'Buyer');
    expect((await career.succession(sam)).replaces.single.name, 'Dana Reyes');
  });

  test('retire with successor; unretire puts it back', () async {
    final old = await dana();
    final sam = await contacts.save(ContactDraft(first: 'Sam', last: 'Okafor', company: 'Halden Tooling'));
    await career.retire(old, successorId: sam);
    var d = (await contacts.loadDetail(old))!;
    expect(d.person.status, PersonStatus.retired);
    expect(d.roles.single.status, RoleStatus.retired);
    expect((await career.succession(old)).replacedBy!.id, sam);
    expect((await career.watchRecent().first).single.$2, PersonStatus.retired);

    await career.unretire(old);
    d = (await contacts.loadDetail(old))!;
    expect(d.person.status, PersonStatus.active);
    expect(d.currentRole!.company, 'Halden Tooling');
  });

  test('bounced email is flagged, never the default target, and suggests a check', () async {
    final old = await contacts.save(
      ContactDraft(first: 'Dana', last: 'Reyes', emails: ['dana@halden.example', 'dana.r@gmail.com']),
    );
    final pt = (await contacts.loadDetail(old))!.emailTarget!;
    expect(pt.value, 'dana@halden.example');
    await career.markBounced(pt.id);
    final d = (await contacts.loadDetail(old))!;
    expect(d.emailTarget!.value, 'dana.r@gmail.com');
    expect((await career.watchPending().first).single.kind, SuggestionKind.bounce);
  });

  test('tracking off (person or everyone) makes no suggestions', () async {
    final a = await dana();
    await (db.update(
      db.people,
    )..where((p) => p.uuid.equals(a))).write(const PeopleCompanion(trackCareer: Value(false)));
    expect(await career.suggestMove(a, company: 'X'), isNull);
    final b = await contacts.save(ContactDraft(first: 'Sam'));
    await db.into(db.appSettings).insert(AppSettingsCompanion.insert(key: 'track_career', value: 'false'));
    expect(await career.suggestMove(b, company: 'X'), isNull);
  });
}
