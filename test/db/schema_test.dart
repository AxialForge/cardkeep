import 'package:card_organizer/core/db/database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('person with role and contact point, tombstone hides it', () async {
    await db.into(db.people).insert(PeopleCompanion.insert(
        uuid: const Value('p1'), first: const Value('Dana'), last: const Value('Reyes')));
    await db.into(db.companies).insert(CompaniesCompanion.insert(
        uuid: const Value('c1'), name: 'Northwind', nameNorm: 'northwind'));
    await db.into(db.roles).insert(RolesCompanion.insert(
        personId: 'p1', companyId: const Value('c1'), title: const Value('VP')));
    await db.into(db.contactPoints).insert(ContactPointsCompanion.insert(
        personId: 'p1', kind: ContactKind.email, value: 'dana@northwind.example'));

    expect((await db.watchPeople().first).single.first, 'Dana');
    expect((await db.select(db.roles).getSingle()).status, RoleStatus.current);

    await db.tombstonePerson('p1');
    expect(await db.watchPeople().first, isEmpty);
  });

  test('foreign keys enforced', () async {
    expect(
      db.into(db.roles).insert(RolesCompanion.insert(personId: 'missing')),
      throwsA(isA<SqliteException>()),
    );
  });
}
