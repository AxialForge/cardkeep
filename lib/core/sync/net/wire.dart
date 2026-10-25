import 'dart:convert';

import '../change_set.dart';
import '../sync_tables.dart';

/// The version of the HTTP protocol (separate from the change set format).
const syncProtocolVersion = 1;

/// The name this app answers to on GET /hello.
const syncAppName = 'CardKeep';

/// Which kind of image a hash is: the rows that name it say so.
const blobKindCard = 'card';
const blobKindLogo = 'logo';

/// hash -> kind for every image the rows in [cs] point at (deleted rows excluded).
Map<String, String> blobKindsOf(ChangeSet cs) {
  final kinds = <String, String>{};
  for (final spec in syncTables) {
    if (spec.blobColumns.isEmpty) continue;
    for (final row in cs.tables[spec.name] ?? const <SyncRow>[]) {
      if (row['deleted_at'] != null) continue;
      for (final c in spec.blobColumns) {
        final h = row[c];
        if (h is String && h.isNotEmpty) kinds[h] = spec.name == 'people' ? blobKindLogo : blobKindCard;
      }
    }
  }
  return kinds;
}

Map<String, Object?> conflictToJson(SyncConflict c) => {
  'id': c.id,
  'peer_id': c.peerId,
  'table': c.table,
  'row_key': c.rowKey,
  'field': c.field,
  'mine': c.mine,
  'theirs': c.theirs,
  'mine_updated_at': c.mineUpdatedAt,
  'theirs_updated_at': c.theirsUpdatedAt,
  'detected_at': c.detectedAt,
};

SyncConflict conflictFromJson(Map<String, Object?> j) => SyncConflict(
  id: j['id'] as String,
  peerId: j['peer_id'] as String,
  table: j['table'] as String,
  rowKey: j['row_key'] as String,
  field: j['field'] as String,
  mine: j['mine'],
  theirs: j['theirs'],
  mineUpdatedAt: j['mine_updated_at'] as int,
  theirsUpdatedAt: j['theirs_updated_at'] as int,
  detectedAt: j['detected_at'] as int,
);

Map<String, Object?> applyResultToJson(ApplyResult r) => {
  'inserted': r.inserted,
  'updated': r.updated,
  'deleted': r.deleted,
  'kept_mine': r.keptMine,
  'merged': r.merged,
  'orphans': r.orphans,
  'complete': r.complete,
  'blobs_needed': r.blobsNeeded,
  'conflicts': [for (final c in r.conflicts) conflictToJson(c)],
};

/// What the other end told us after applying a pushed page.
class PushReply {
  final int inserted, updated, deleted;
  final bool complete;
  final List<String> blobsNeeded;
  final List<SyncConflict> conflicts;
  const PushReply({
    this.inserted = 0,
    this.updated = 0,
    this.deleted = 0,
    this.complete = true,
    this.blobsNeeded = const [],
    this.conflicts = const [],
  });

  factory PushReply.fromJson(Map<String, Object?> j) => PushReply(
    inserted: j['inserted'] as int? ?? 0,
    updated: j['updated'] as int? ?? 0,
    deleted: j['deleted'] as int? ?? 0,
    complete: j['complete'] as bool? ?? true,
    blobsNeeded: [for (final b in (j['blobs_needed'] as List? ?? const [])) b as String],
    conflicts: [
      for (final c in (j['conflicts'] as List? ?? const [])) conflictFromJson((c as Map).cast<String, Object?>()),
    ],
  );
}

Object? decodeJsonBody(List<int> bytes) {
  try {
    return jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw const SyncFormatException('The message was damaged.');
  }
}
