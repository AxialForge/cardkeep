import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    People,
    Companies,
    Roles,
    ContactPoints,
    Successions,
    ChangeSuggestions,
    Cards,
    Events,
    ScanSessions,
    Tags,
    PersonTags,
    Devices,
    AppSettings,
    NotDuplicates,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'card_organizer'));

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement('CREATE INDEX idx_companies_name_norm ON companies (name_norm)');
      await customStatement('CREATE INDEX idx_contact_points_value ON contact_points (value)');
      await customStatement('CREATE INDEX idx_contact_points_person ON contact_points (person_id)');
      await customStatement('CREATE INDEX idx_roles_person ON roles (person_id)');
      // Search index, one row per live person, rebuilt by ContactsRepository.
      await customStatement(
        "CREATE VIRTUAL TABLE person_search USING fts5(person_id UNINDEXED, body, tokenize = 'unicode61 remove_diacritics 2')",
      );
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.createTable(notDuplicates);
      if (from < 3) {
        await m.addColumn(people, people.middle);
        await m.addColumn(people, people.logoSha256);
        await m.addColumn(people, people.extrasJson);
        await m.addColumn(contactPoints, contactPoints.extension);
      }
      if (from < 4) {
        // Places (S14b): every existing row is a person.
        await m.addColumn(people, people.kind);
        await m.addColumn(people, people.placeCategory);
        await m.addColumn(people, people.hours);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Tombstone, never hard-delete, so sync can propagate it (spec §10).
  Future<void> tombstonePerson(String id) async {
    final now = DateTime.now();
    await (update(
      people,
    )..where((p) => p.uuid.equals(id))).write(PeopleCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }
}
