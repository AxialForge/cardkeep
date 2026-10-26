import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../sync/sync_triggers.dart';
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
    PlaceCategories,
    SyncConflicts,
    SyncBase,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'card_organizer'));

  /// The schema version of this build; read by main() before the database opens
  /// so a copy can be kept when an upgrade is about to run.
  static const currentSchemaVersion = 6;

  @override
  int get schemaVersion => currentSchemaVersion;

  /// The built-in place categories, in their default order (S14b.6).
  Future<void> seedPlaceCategories() async {
    for (final (i, c) in PlaceCategory.values.indexed) {
      await into(placeCategories).insert(
        PlaceCategoriesCompanion.insert(
          id: c.name,
          label: '${c.name[0].toUpperCase()}${c.name.substring(1)}',
          sort: Value(c == PlaceCategory.other ? 1000 : i),
          builtIn: const Value(true),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }

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
      await seedPlaceCategories();
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
      if (from < 5) {
        // Editable place categories (S14b.6); existing places keep their ids.
        await m.createTable(placeCategories);
        await seedPlaceCategories();
      }
      if (from < 6) {
        // Sync (0.8): place categories gain change tracking, devices gain watermarks.
        // A database older than v5 made place_categories a moment ago, new columns
        // and all, so only add what is missing.
        Future<bool> has(String table, String column) async =>
            (await customSelect('PRAGMA table_info($table)').get()).any((r) => r.read<String>('name') == column);
        if (!await has('place_categories', 'updated_at')) await m.addColumn(placeCategories, placeCategories.updatedAt);
        if (!await has('place_categories', 'deleted_at')) await m.addColumn(placeCategories, placeCategories.deletedAt);
        if (!await has('devices', 'their_watermark')) await m.addColumn(devices, devices.theirWatermark);
        if (!await has('devices', 'my_watermark')) await m.addColumn(devices, devices.myWatermark);
        if (!await has('devices', 'paired_at')) await m.addColumn(devices, devices.pairedAt);
        if (!await has('devices', 'clock_offset_seconds')) await m.addColumn(devices, devices.clockOffsetSeconds);
        // Categories the owner added in v5 have never been stamped; do it now so
        // they reach the other device. Built-ins stay 0 on every phone.
        await customStatement(
          "UPDATE place_categories SET updated_at = CAST(strftime('%s', 'now') AS INTEGER) WHERE built_in = 0 AND updated_at = 0",
        );
        await m.createTable(syncConflicts);
        await m.createTable(syncBase);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // Idempotent: also covers databases created before the triggers existed.
      await createSyncTriggers(this);
    },
  );

  /// Tombstone, never hard-delete, so sync can propagate it (spec §10).
  Future<void> tombstonePerson(String id, {DateTime? at}) async {
    final now = at ?? DateTime.now();
    await (update(
      people,
    )..where((p) => p.uuid.equals(id))).write(PeopleCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }
}
