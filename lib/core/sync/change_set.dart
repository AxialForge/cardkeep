import 'dart:convert';

/// The wire format version. A device refuses a change set from a newer one.
const syncFormatVersion = 1;

/// Thrown for a change set that cannot be understood (wrong version or shape).
class SyncFormatException implements Exception {
  final String message;
  const SyncFormatException(this.message);
  @override
  String toString() => message;
}

/// A row as exchanged: column name -> int, String or null. Dates are unix
/// seconds and booleans 0 or 1, exactly as they sit in the database.
typedef SyncRow = Map<String, Object?>;

/// The changes one device sends another (GET /changes and POST /changes carry
/// this same JSON).
///
/// `since` and `until` are seconds on the sender's clock: rows with
/// updated_at >= since, up to the moment the set was built. A set can come in
/// pages; `next` is where the following page starts, null on the last one.
class ChangeSet {
  final int version;
  final String deviceId;
  final int since;
  final int until;
  final Map<String, List<SyncRow>> tables;

  /// sha256 of every image the rows in this set point at (not deleted rows).
  final List<String> blobs;

  /// Where this page started (null for the first page).
  final String? cursor;

  /// Where the next page starts, or null when this is the last page.
  final String? next;

  const ChangeSet({
    this.version = syncFormatVersion,
    required this.deviceId,
    required this.since,
    required this.until,
    required this.tables,
    this.blobs = const [],
    this.cursor,
    this.next,
  });

  int get rowCount => tables.values.fold(0, (n, rows) => n + rows.length);
  bool get isLast => next == null;

  Map<String, Object?> toJson() => {
    'v': version,
    'device_id': deviceId,
    'since': since,
    'until': until,
    'cursor': cursor,
    'next': next,
    'tables': tables,
    'blobs': blobs,
  };

  String encode() => jsonEncode(toJson());

  factory ChangeSet.fromJson(Map<String, Object?> j) {
    final v = j['v'];
    if (v is! int) throw const SyncFormatException('Not a CardKeep change set (no version).');
    if (v > syncFormatVersion) {
      throw SyncFormatException('This change set is from a newer CardKeep (format $v). Update CardKeep first.');
    }
    final device = j['device_id'];
    final since = j['since'];
    final until = j['until'];
    final tables = j['tables'];
    if (device is! String || since is! int || until is! int || tables is! Map) {
      throw const SyncFormatException('The change set is damaged.');
    }
    return ChangeSet(
      version: v,
      deviceId: device,
      since: since,
      until: until,
      cursor: j['cursor'] as String?,
      next: j['next'] as String?,
      blobs: [for (final b in (j['blobs'] as List? ?? const [])) b as String],
      tables: {
        for (final e in tables.entries)
          e.key as String: [
            for (final r in (e.value as List)) {for (final c in (r as Map).entries) c.key as String: c.value as Object?},
          ],
      },
    );
  }

  factory ChangeSet.decode(String text) {
    try {
      final j = jsonDecode(text);
      if (j is! Map<String, dynamic>) throw const SyncFormatException('The change set is damaged.');
      return ChangeSet.fromJson(j);
    } on FormatException {
      throw const SyncFormatException('The change set is damaged.');
    }
  }

  /// This set cut into pieces of at most [rows] rows, parents first. For tests
  /// and for sending over a flaky link; only the last piece has `next == null`.
  List<ChangeSet> split(int rows) {
    final flat = [
      for (final e in tables.entries)
        for (final r in e.value) (e.key, r),
    ];
    final pieces = <ChangeSet>[];
    for (var i = 0; i == 0 || i < flat.length; i += rows) {
      final part = <String, List<SyncRow>>{};
      for (final (name, row) in flat.skip(i).take(rows)) {
        (part[name] ??= []).add(row);
      }
      final last = i + rows >= flat.length;
      pieces.add(
        ChangeSet(
          version: version,
          deviceId: deviceId,
          since: since,
          until: until,
          tables: part,
          blobs: blobs,
          cursor: i == 0 ? cursor : 'piece:$i',
          next: last ? next : 'piece:${i + rows}',
        ),
      );
    }
    return pieces;
  }
}

/// A field that both devices changed within the conflict window. The row keeps
/// this device's value until [SyncEngine.resolveMine] or [SyncEngine.resolveTheirs].
class SyncConflict {
  final String id;
  final String peerId;
  final String table;
  final String rowKey;
  final String field;
  final Object? mine;
  final Object? theirs;
  final int mineUpdatedAt;
  final int theirsUpdatedAt;
  final int detectedAt;
  final int? resolvedAt;
  final String? resolution;

  const SyncConflict({
    required this.id,
    required this.peerId,
    required this.table,
    required this.rowKey,
    required this.field,
    required this.mine,
    required this.theirs,
    required this.mineUpdatedAt,
    required this.theirsUpdatedAt,
    required this.detectedAt,
    this.resolvedAt,
    this.resolution,
  });

  bool get isOpen => resolvedAt == null;
}

/// What one apply() did.
class ApplyResult {
  /// New rows, rows changed by the peer, rows deleted by the peer.
  final int inserted, updated, deleted;

  /// Rows where this device's version stayed (it is newer, or the peer's was older).
  final int keptMine;

  /// Fields recorded as conflicts by this apply (new or still open).
  final List<SyncConflict> conflicts;

  /// Same-name rows (companies, tags, categories, tag links) folded into one.
  final int merged;

  /// Rows skipped because the row they belong to is not here and was not sent.
  final int orphans;

  /// People whose search entry needs rebuilding.
  final Set<String> peopleChanged;

  /// Images the sent rows point at that this device does not have yet.
  final List<String> blobsNeeded;

  /// True when this was the last page, so the peer's watermark moved.
  final bool complete;

  const ApplyResult({
    this.inserted = 0,
    this.updated = 0,
    this.deleted = 0,
    this.keptMine = 0,
    this.conflicts = const [],
    this.merged = 0,
    this.orphans = 0,
    this.peopleChanged = const {},
    this.blobsNeeded = const [],
    this.complete = true,
  });

  int get changes => inserted + updated + deleted;
}
