import 'package:drift/drift.dart';

import 'sync_tables.dart';

/// app_settings key: '1' while a change set is being applied, so the triggers
/// below leave the peer's timestamps alone.
const syncApplyingKey = 'sync.applying';

/// One trigger per synced table: any UPDATE that does not set updated_at itself
/// stamps it with the current time. This is the safety net behind the
/// repositories' own stamps, so no write path can change a row without sync
/// seeing it (test/sync/sync_tables_test.dart checks every table has one).
String touchTriggerName(String table) => 'trg_${table}_touch';

Future<void> createSyncTriggers(GeneratedDatabase db) async {
  for (final t in syncTables) {
    await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS ${touchTriggerName(t.name)}
AFTER UPDATE ON ${t.name}
WHEN NEW.updated_at IS OLD.updated_at
 AND IFNULL((SELECT value FROM app_settings WHERE key = '$syncApplyingKey'), '0') <> '1'
BEGIN
  UPDATE ${t.name} SET updated_at = CAST(strftime('%s', 'now') AS INTEGER) WHERE ${t.key} = NEW.${t.key};
END''');
  }
  // A custom category added on this phone starts with updated_at 0 (the column
  // default); stamp it. Built-in rows stay 0 so both phones seed identical rows.
  await db.customStatement('''
CREATE TRIGGER IF NOT EXISTS trg_place_categories_new
AFTER INSERT ON place_categories
WHEN NEW.updated_at = 0 AND NEW.built_in = 0
 AND IFNULL((SELECT value FROM app_settings WHERE key = '$syncApplyingKey'), '0') <> '1'
BEGIN
  UPDATE place_categories SET updated_at = CAST(strftime('%s', 'now') AS INTEGER) WHERE id = NEW.id;
END''');
}
