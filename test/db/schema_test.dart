import 'package:card_organizer/core/db/database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('foreign keys enforced', () async {
    expect(db.into(db.roles).insert(RolesCompanion.insert(personId: 'missing')), throwsA(isA<SqliteException>()));
  });

  test('person_tags is unique per pair', () async {
    await db.into(db.people).insert(PeopleCompanion.insert(uuid: const Value('p1')));
    await db.into(db.tags).insert(TagsCompanion.insert(uuid: const Value('t1'), name: 'Expo'));
    await db.into(db.personTags).insert(PersonTagsCompanion.insert(personId: 'p1', tagId: 't1'));
    expect(
      db.into(db.personTags).insert(PersonTagsCompanion.insert(personId: 'p1', tagId: 't1')),
      throwsA(isA<SqliteException>()),
    );
  });

  test('fts5 search table exists', () async {
    await db.customStatement("INSERT INTO person_search (person_id, body) VALUES ('x', 'Halden Tooling')");
    final r = await db.customSelect("SELECT person_id FROM person_search WHERE person_search MATCH 'hald*'").get();
    expect(r.single.read<String>('person_id'), 'x');
  });
}
