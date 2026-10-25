import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/sync/sync_tables.dart';
import 'package:card_organizer/core/sync/sync_triggers.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sync only works if every write to a synced table moves updated_at (S16.1).
/// These tests turn a new table, or a table without that, into a failing test
/// instead of a silent hole in sync.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> updatedAt(String table, String keyCol, String key) async =>
      (await db
              .customSelect(
                'SELECT updated_at AS u FROM $table WHERE $keyCol = ?',
                variables: [Variable.withString(key)],
              )
              .getSingle())
          .read<int>('u');

  test('every table is either synced or on the not-synced list, with a reason', () {
    final all = {for (final t in db.allTables) t.actualTableName};
    final decided = {...syncTables.map((t) => t.name), ...notSynced.keys};
    expect(all.difference(decided), isEmpty, reason: 'a new table needs a decision: add it to syncTables or notSynced');
    expect(decided.difference(all), isEmpty, reason: 'a table listed here no longer exists');
    expect(syncTables.map((t) => t.name).toSet().intersection(notSynced.keys.toSet()), isEmpty);
  });

  test(
    'every synced table has its key, updated_at, a tombstone column and a touch trigger; parents come first',
    () async {
      final triggers = {
        for (final r in await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'trigger'").get())
          r.read<String>('name'),
      };
      for (final spec in syncTables) {
        final cols = {
          for (final r in await db.customSelect('PRAGMA table_info(${spec.name})').get()) r.read<String>('name'),
        };
        expect(cols, containsAll([spec.key, 'updated_at', 'deleted_at']), reason: spec.name);
        expect(triggers, contains(touchTriggerName(spec.name)), reason: '${spec.name} has no touch trigger');
        for (final e in spec.refs.entries) {
          expect(cols, contains(e.key), reason: '${spec.name} refs ${e.key}');
          final parent = syncTables.indexWhere((t) => t.name == e.value);
          expect(parent, isNonNegative, reason: '${spec.name}.${e.key} points at ${e.value}, which does not sync');
          expect(
            parent <= syncTables.indexWhere((t) => t.name == spec.name),
            isTrue,
            reason: '${e.value} must come before ${spec.name}',
          );
        }
        for (final c in spec.blobColumns) {
          expect(cols, contains(c), reason: '${spec.name} blob column $c');
        }
      }
    },
  );

  test(
    'a write that forgets updated_at is stamped, one that sets it is left alone, the apply flag silences it',
    () async {
      await db.customStatement(
        "INSERT INTO people (uuid, first, last, created_at, updated_at) VALUES ('p1', 'Dana', 'Reyes', 100, 100)",
      );
      await db.customStatement("UPDATE people SET notes = 'x' WHERE uuid = 'p1'");
      expect(
        await updatedAt('people', 'uuid', 'p1'),
        greaterThan(1000000000),
        reason: 'a forgotten stamp is filled in with the time',
      );

      await db.customStatement("UPDATE people SET notes = 'y', updated_at = 555 WHERE uuid = 'p1'");
      expect(await updatedAt('people', 'uuid', 'p1'), 555);

      await db.customStatement("INSERT INTO app_settings (key, value) VALUES ('$syncApplyingKey', '1')");
      await db.customStatement("UPDATE people SET notes = 'z' WHERE uuid = 'p1'");
      expect(
        await updatedAt('people', 'uuid', 'p1'),
        555,
        reason: "while a change set is applied, the peer's time stays",
      );
    },
  );

  test('every synced table stamps updated_at when a data column changes (by plain SQL)', () async {
    await db.customStatement(
      "INSERT INTO companies (uuid, name, name_norm, updated_at) VALUES ('co', 'Acme', 'acme', 1)",
    );
    await db.customStatement("INSERT INTO tags (uuid, name, updated_at) VALUES ('tg', 'Hot', 1)");
    await db.customStatement(
      "INSERT INTO events (uuid, name, type, start_date, end_date, updated_at) VALUES ('ev', 'Show', 'tradeShow', 1, 2, 1)",
    );
    await db.customStatement("INSERT INTO scan_sessions (uuid, event_id, updated_at) VALUES ('ss', 'ev', 1)");
    await db.customStatement("INSERT INTO people (uuid, first, updated_at) VALUES ('pe', 'A', 1)");
    await db.customStatement(
      "INSERT INTO roles (uuid, person_id, company_id, updated_at) VALUES ('ro', 'pe', 'co', 1)",
    );
    await db.customStatement(
      "INSERT INTO contact_points (uuid, person_id, role_id, kind, value, updated_at) VALUES ('cp', 'pe', 'ro', 'email', 'a@b.c', 1)",
    );
    await db.customStatement(
      "INSERT INTO successions (uuid, company_id, predecessor_person_id, updated_at) VALUES ('su', 'co', 'pe', 1)",
    );
    await db.customStatement(
      "INSERT INTO change_suggestions (uuid, person_id, kind, source, updated_at) VALUES ('cs', 'pe', 'moved', 'scan', 1)",
    );
    await db.customStatement(
      "INSERT INTO cards (uuid, person_id, front_sha256, scan_session_id, updated_at) VALUES ('ca', 'pe', 'h', 'ss', 1)",
    );
    await db.customStatement(
      "INSERT INTO person_tags (uuid, person_id, tag_id, updated_at) VALUES ('pt', 'pe', 'tg', 1)",
    );
    await db.customStatement("INSERT INTO not_duplicates (uuid, pair_key, updated_at) VALUES ('nd', 'a|b', 1)");
    await db.customStatement("INSERT INTO place_categories (id, label, updated_at) VALUES ('c_1', 'Bakery', 1)");

    const changes = <String, (String, String)>{
      'companies': ('co', "name = 'Acme 2'"),
      'tags': ('tg', "color = '#000000'"),
      'events': ('ev', "notes = 'n'"),
      'scan_sessions': ('ss', 'ended_at = 5'),
      'people': ('pe', "notes = 'n'"),
      'roles': ('ro', "title = 'Boss'"),
      'contact_points': ('cp', "label = 'Work'"),
      'successions': ('su', "note = 'n'"),
      'change_suggestions': ('cs', "payload_json = '{\"a\":1}'"),
      'cards': ('ca', "ocr_json = '{\"a\":1}'"),
      'person_tags': ('pt', 'deleted_at = 9'),
      'not_duplicates': ('nd', 'deleted_at = 9'),
      'place_categories': ('c_1', "label = 'Bakeries'"),
    };
    expect(changes.keys.toSet(), syncTables.map((t) => t.name).toSet(), reason: 'every synced table is covered here');
    for (final spec in syncTables) {
      final (key, set) = changes[spec.name]!;
      await db.customStatement('UPDATE ${spec.name} SET $set WHERE ${spec.key} = ?', [key]);
      expect(
        await updatedAt(spec.name, spec.key, key),
        greaterThan(1000000000),
        reason: '${spec.name} was not stamped',
      );
    }
  });

  test('a custom place category added on this device is stamped; a built-in one stays 0 on both devices', () async {
    await db.customStatement("INSERT INTO place_categories (id, label) VALUES ('c_9', 'Florist')");
    expect(await updatedAt('place_categories', 'id', 'c_9'), greaterThan(1000000000));
    expect(await updatedAt('place_categories', 'id', 'store'), 0, reason: 'built-ins seed identically everywhere');
  });
}
