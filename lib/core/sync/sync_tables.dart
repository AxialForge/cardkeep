/// Which tables travel between devices, in the order they are applied (parents
/// before children), and how their rows point at each other.
library;

/// One synced table. Rows are exchanged as plain column maps (ints, strings,
/// null; dates are unix seconds, booleans 0 or 1), so no per-table code is
/// needed to read or write them.
class SyncTableSpec {
  /// SQL table name, also the key in a change set.
  final String name;

  /// The column that identifies a row on every device.
  final String key;

  /// Columns that hold another synced row's key: column -> table it points at.
  /// A rewrite of a key (two devices made the same company) follows these.
  final Map<String, String> refs;

  /// Columns that name an image by its sha256, so the image travels too.
  final List<String> blobColumns;

  /// The name that says two rows are the same thing made on two devices.
  final String? naturalKey;

  const SyncTableSpec(
    this.name, {
    this.key = 'uuid',
    this.refs = const {},
    this.blobColumns = const [],
    this.naturalKey,
  });
}

/// Parents first. `people` points at events and places categories, so those come before it.
const syncTables = <SyncTableSpec>[
  SyncTableSpec('place_categories', key: 'id', naturalKey: 'label'),
  SyncTableSpec('companies', naturalKey: 'name_norm'),
  SyncTableSpec('tags', naturalKey: 'name'),
  SyncTableSpec('events'),
  SyncTableSpec('scan_sessions', refs: {'event_id': 'events'}),
  SyncTableSpec(
    'people',
    refs: {'met_event_id': 'events', 'introduced_by_person_id': 'people', 'place_category': 'place_categories'},
    blobColumns: ['logo_sha256'],
  ),
  SyncTableSpec('roles', refs: {'person_id': 'people', 'company_id': 'companies'}),
  SyncTableSpec('contact_points', refs: {'person_id': 'people', 'role_id': 'roles'}),
  SyncTableSpec(
    'successions',
    refs: {'company_id': 'companies', 'predecessor_person_id': 'people', 'successor_person_id': 'people'},
  ),
  SyncTableSpec('change_suggestions', refs: {'person_id': 'people'}),
  SyncTableSpec(
    'cards',
    refs: {'person_id': 'people', 'scan_session_id': 'scan_sessions'},
    blobColumns: ['front_sha256', 'back_sha256'],
  ),
  SyncTableSpec('person_tags', refs: {'person_id': 'people', 'tag_id': 'tags'}),
  SyncTableSpec('not_duplicates', naturalKey: 'pair_key'),
];

/// Tables that never sync, and why. Every table in the database must be in
/// [syncTables] or here: a new table forces a decision (test/sync/sync_tables_test.dart).
const notSynced = <String, String>{
  'app_settings': 'per-device settings (place categories sync through their own table)',
  'devices': 'the list of paired devices is local to each device',
  'sync_conflicts': 'a conflict is this device\'s to resolve',
  'sync_base': 'bookkeeping for the merge, per peer',
};

/// Columns never compared when two versions of a row are merged.
const metaColumns = {'created_at', 'updated_at', 'deleted_at'};

SyncTableSpec specOf(String table) => syncTables.firstWhere((t) => t.name == table);

/// The tables whose pairs are stored with SQL UNIQUE constraints, so a duplicate
/// must be removed, not tombstoned.
const uniqueNaturalKey = {'person_tags', 'not_duplicates'};
