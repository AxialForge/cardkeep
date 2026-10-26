import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/database.dart';
import 'blob_transfer.dart';
import 'change_set.dart';
import 'sync_tables.dart';
import 'sync_triggers.dart';

/// A device this one is paired with.
class SyncPeer {
  final String id;
  final String name;
  final int theirWatermark;
  final int myWatermark;
  final int clockOffsetSeconds;
  final DateTime? lastSyncAt;
  final DateTime? pairedAt;

  const SyncPeer({
    required this.id,
    required this.name,
    required this.theirWatermark,
    required this.myWatermark,
    required this.clockOffsetSeconds,
    this.lastSyncAt,
    this.pairedAt,
  });
}

/// The sync engine: builds the changes another device has not seen, and merges
/// the changes it sends back. No network, no screens: it reads and writes the
/// database and nothing else, so two engines on two in-memory databases can be
/// tested against each other. (0.8 step 1; the transport, pairing and screens
/// come later.)
///
/// The rules, in short (design note in docs/ROADMAP.md, S16):
///  * Every synced row has a uuid, updated_at (seconds) and a tombstone.
///    SQLite triggers stamp updated_at on any write that forgets to.
///  * A change set holds the rows with updated_at >= the peer's watermark. The
///    edge is inclusive and apply is idempotent, so a row is never missed.
///  * Merge is last-write-wins per field, using the peer's clock corrected by
///    the offset measured at pairing. A per-peer "base" copy of each row tells
///    which side changed which field, so edits to different fields both stay.
///  * The same field changed on both sides within [conflictWindow] is kept as a
///    conflict (this device's value stays) until the owner picks a side.
///  * A deletion and an edit: the later one wins; a tie goes to the deletion.
///  * Two devices that each made "Acme" or the tag "Hot" end up with one: the
///    smaller uuid is kept, the other is folded into it.
class SyncEngine {
  final AppDatabase db;

  /// Where finished images are looked up, so a change set can say which ones the
  /// other device still needs. Optional: without it no image is reported missing.
  final BlobSink? blobs;

  /// The clock, in tests a fake one.
  final DateTime Function() clock;

  /// Two edits of the same field closer together than this are a conflict.
  final Duration conflictWindow;

  /// Rows per page of a change set.
  final int pageSize;

  /// Called with the people whose rows changed, so their search entries can be rebuilt.
  final Future<void> Function(Set<String> personIds)? reindexPeople;

  SyncEngine(
    this.db, {
    this.blobs,
    DateTime Function()? clock,
    this.conflictWindow = const Duration(minutes: 2),
    this.pageSize = 5000,
    this.reindexPeople,
  }) : clock = clock ?? DateTime.now;

  int _now() => clock().millisecondsSinceEpoch ~/ 1000;

  final Map<String, List<String>> _columnCache = {};

  Future<List<String>> _columns(String table) async => _columnCache[table] ??= [
    for (final r in await db.customSelect('PRAGMA table_info($table)').get()) r.read<String>('name'),
  ];

  // ---------------------------------------------------------------- identity

  /// This device's id, made once and kept in settings.
  Future<String> myDeviceId() async {
    final r = await db.customSelect("SELECT value FROM app_settings WHERE key = 'sync.device_id'").getSingleOrNull();
    if (r != null) return r.read<String>('value');
    final id = uuidGen.v4();
    await db.customStatement("INSERT INTO app_settings (key, value) VALUES ('sync.device_id', ?)", [id]);
    return id;
  }

  Future<SyncPeer?> peer(String id) async {
    final r = await db
        .customSelect('SELECT * FROM devices WHERE uuid = ?', variables: [Variable.withString(id)])
        .getSingleOrNull();
    return r == null ? null : _peerOf(r.data);
  }

  Future<List<SyncPeer>> peers() async => [
    for (final r in await db.customSelect('SELECT * FROM devices WHERE deleted_at IS NULL ORDER BY name').get())
      _peerOf(r.data),
  ];

  SyncPeer _peerOf(Map<String, Object?> d) => SyncPeer(
    id: d['uuid'] as String,
    name: d['name'] as String,
    theirWatermark: d['their_watermark'] as int? ?? 0,
    myWatermark: d['my_watermark'] as int? ?? 0,
    clockOffsetSeconds: d['clock_offset_seconds'] as int? ?? 0,
    lastSyncAt: d['last_sync_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((d['last_sync_at'] as int) * 1000),
    pairedAt: d['paired_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch((d['paired_at'] as int) * 1000),
  );

  /// Remembers a paired device. [clockOffsetSeconds] is the peer's clock minus
  /// this one's, measured at pairing; pairing again refreshes it.
  Future<void> registerPeer(
    String id, {
    required String name,
    String platform = 'android',
    String certFingerprint = '',
    int clockOffsetSeconds = 0,
  }) async {
    final now = _now();
    if (await peer(id) == null) {
      await db.customStatement(
        'INSERT INTO devices (uuid, name, platform, cert_fingerprint, paired_at, clock_offset_seconds, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [id, name, platform, certFingerprint, now, clockOffsetSeconds, now, now],
      );
    } else {
      await db.customStatement(
        'UPDATE devices SET name = ?, platform = ?, cert_fingerprint = ?, clock_offset_seconds = ?, updated_at = ? WHERE uuid = ?',
        [name, platform, certFingerprint, clockOffsetSeconds, now, id],
      );
    }
  }

  /// Forgets a device and what was known about it; its next sync starts over.
  Future<void> unpair(String id) => db.transaction(() async {
    await db.customStatement('DELETE FROM sync_base WHERE peer_id = ?', [id]);
    await db.customStatement('DELETE FROM sync_conflicts WHERE peer_id = ?', [id]);
    await db.customStatement('DELETE FROM devices WHERE uuid = ?', [id]);
  });

  // ------------------------------------------------------------------- build

  /// The changes [peerId] has not seen: rows with updated_at >= its watermark
  /// (or [since]). [cursor] and the set's `next` page through a big library.
  Future<ChangeSet> buildChanges({String? peerId, int? since, String? cursor, int? limit}) async {
    final from = since ?? (peerId == null ? 0 : (await peer(peerId))?.myWatermark ?? 0);
    final max = limit ?? pageSize;
    final start = _Cursor.parse(cursor);
    final out = <String, List<SyncRow>>{};
    final hashes = <String>{};
    var left = max;
    String? next;
    for (var ti = start.table; ti < syncTables.length && left > 0; ti++) {
      final spec = syncTables[ti];
      final after = ti == start.table && start.hasPosition;
      final rows = await db
          .customSelect(
            'SELECT * FROM ${spec.name} WHERE updated_at >= ?'
            '${after ? ' AND (updated_at > ? OR (updated_at = ? AND ${spec.key} > ?))' : ''} '
            'ORDER BY updated_at, ${spec.key} LIMIT ?',
            variables: [
              Variable.withInt(from),
              if (after) ...[
                Variable.withInt(start.updatedAt),
                Variable.withInt(start.updatedAt),
                Variable.withString(start.key),
              ],
              Variable.withInt(left + 1),
            ],
          )
          .get();
      final take = rows.length > left ? rows.sublist(0, left) : rows;
      if (take.isNotEmpty) out[spec.name] = [for (final r in take) Map<String, Object?>.of(r.data)];
      for (final r in take) {
        if (r.data['deleted_at'] != null) continue;
        for (final c in spec.blobColumns) {
          final h = r.data[c];
          if (h is String && h.isNotEmpty) hashes.add(h);
        }
      }
      left -= take.length;
      if (left == 0 && take.isNotEmpty) {
        final last = take.last.data;
        next = _Cursor(ti, last['updated_at'] as int, last[spec.key] as String).encode();
        break;
      }
    }
    return ChangeSet(
      deviceId: await myDeviceId(),
      since: from,
      until: _now(),
      tables: out,
      blobs: hashes.toList()..sort(),
      cursor: cursor,
      next: next,
    );
  }

  /// Marks [sent] as delivered: the peer now has these versions of the rows,
  /// and (on the last page) its watermark moves to the set's `until`.
  ///
  /// [peerConflicts] are the conflicts the peer reported when it applied [sent]
  /// (ApplyResult.conflicts): it kept its own value for those fields, so they are
  /// not recorded as shared and the next merge still sees both sides as changed.
  Future<void> acknowledge(String peerId, ChangeSet sent, {List<SyncConflict> peerConflicts = const []}) =>
      db.transaction(() async {
        final open = await _openConflictFields(peerId);
        for (final c in peerConflicts) {
          (open['${c.table}|${c.rowKey}'] ??= {}).add(c.field);
        }
        for (final e in sent.tables.entries) {
          final spec = specOf(e.key);
          for (final row in e.value) {
            final key = row[spec.key] as String;
            await _storeBase(peerId, e.key, key, _baseOf(spec, row), keepOldFor: open['${e.key}|$key'] ?? const {});
          }
        }
        if (sent.isLast) {
          await db.customStatement('UPDATE devices SET my_watermark = ? WHERE uuid = ?', [sent.until, peerId]);
        }
      });

  // ------------------------------------------------------------------- apply

  /// Merges a change set from a paired device. Idempotent and all-or-nothing:
  /// apply the same set twice and the second does nothing; if it throws, nothing
  /// changed. [clockOffset] (peer clock minus ours, seconds) defaults to the one
  /// stored when pairing.
  Future<ApplyResult> apply(ChangeSet cs, {int? clockOffset}) async {
    if (cs.version > syncFormatVersion) {
      throw SyncFormatException(
        'This change set is from a newer CardKeep (format ${cs.version}). Update CardKeep first.',
      );
    }
    if (cs.deviceId == await myDeviceId()) throw const SyncFormatException('That change set came from this device.');
    var known = await peer(cs.deviceId);
    if (known == null) {
      await registerPeer(cs.deviceId, name: 'Paired device', clockOffsetSeconds: clockOffset ?? 0);
      known = await peer(cs.deviceId);
    }
    final offset = clockOffset ?? known!.clockOffsetSeconds;
    final run = _Run(cs.deviceId, offset, _now());
    late ApplyResult result;
    await db.transaction(() async {
      await db.customStatement("INSERT OR REPLACE INTO app_settings (key, value) VALUES ('$syncApplyingKey', '1')");
      await db.customStatement('PRAGMA defer_foreign_keys = ON');
      // Conflicts about the order of built-in place categories were raised by
      // earlier builds; that order is local now, so close any still open.
      await db.customStatement(
        "UPDATE sync_conflicts SET resolved_at = ?, resolution = 'sync' WHERE table_name = 'place_categories' "
        "AND field = 'sort' AND resolved_at IS NULL AND row_key IN (SELECT id FROM place_categories WHERE built_in = 1)",
        [run.now],
      );
      for (final spec in syncTables) {
        for (final row in cs.tables[spec.name] ?? const <SyncRow>[]) {
          await _applyRow(spec, Map<String, Object?>.of(row), run);
        }
      }
      await db.customStatement("DELETE FROM app_settings WHERE key = '$syncApplyingKey'");
      if (cs.isLast) {
        await db.customStatement(
          'UPDATE devices SET their_watermark = ?, last_sync_at = ?, clock_offset_seconds = ? WHERE uuid = ?',
          [cs.until, run.now, offset, cs.deviceId],
        );
      }
      final needed = blobs == null ? <String>[] : await missingBlobs(blobs!, cs.blobs);
      result = ApplyResult(
        inserted: run.inserted,
        updated: run.updated,
        deleted: run.deleted,
        keptMine: run.keptMine,
        conflicts: run.conflicts,
        merged: run.merged,
        orphans: run.orphans,
        peopleChanged: run.people,
        blobsNeeded: needed,
        complete: cs.isLast,
      );
    });
    db.markTablesUpdated([
      for (final t in db.allTables)
        if (run.touchedTables.contains(t.actualTableName)) t,
    ]);
    if (run.people.isNotEmpty) await reindexPeople?.call(run.people);
    return result;
  }

  Future<void> _applyRow(SyncTableSpec spec, SyncRow incoming, _Run run) async {
    final cols = await _columns(spec.name);
    incoming.removeWhere((k, _) => !cols.contains(k));
    var key = incoming[spec.key] as String;
    // Follow keys rewritten earlier in this set (a twin folded into another row).
    for (final e in spec.refs.entries) {
      final v = incoming[e.key];
      if (v is String) incoming[e.key] = run.remap[e.value]?[v] ?? v;
    }
    // The peer's clock, corrected to ours and never later than now.
    final tp = (((incoming['updated_at'] as int?) ?? 0) - run.offset).clamp(0, run.now).toInt();
    incoming['updated_at'] = tp;
    final deletedAt = incoming['deleted_at'];
    if (deletedAt is int) incoming['deleted_at'] = (deletedAt - run.offset).clamp(0, run.now).toInt();

    final twin = await _findTwin(spec, incoming, key);
    if (twin != null) {
      final twinKey = twin[spec.key] as String;
      if (_winner(spec, incoming, twin) == key) {
        await _foldInto(spec, loser: twin, winnerKey: key, run: run);
      } else {
        (run.remap[spec.name] ??= {})[key] = twinKey;
        run.merged++;
        // A company, tag or category that loses to its twin just disappears into
        // it. A tag link or a "not the same person" pair carries a deletion that
        // must still reach the row that stays, so that is merged in.
        if (!uniqueNaturalKey.contains(spec.name)) return;
        key = twinKey;
        incoming[spec.key] = twinKey;
      }
    }

    final local = await _row(spec, key);
    if (local == null) {
      if (!await _parentsExist(spec, incoming)) {
        run.orphans++;
        return;
      }
      await _insert(spec, incoming);
      incoming['deleted_at'] == null ? run.inserted++ : run.deleted++;
      run.touch(spec.name, incoming);
      await _storeBase(run.peer, spec.name, key, _baseOf(spec, incoming));
      return;
    }
    await _mergeBoth(spec, local, incoming, key, tp, run);
  }

  Future<void> _mergeBoth(SyncTableSpec spec, SyncRow local, SyncRow incoming, String key, int tp, _Run run) async {
    final tl = local['updated_at'] as int? ?? 0;
    final delL = local['deleted_at'] != null;
    final delP = incoming['deleted_at'] != null;
    if (delL || delP) {
      if (delL && delP) {
        run.keptMine++;
        return;
      }
      // A deletion against an edit: the later one wins, a tie goes to the deletion.
      final takeTheirs = tp > tl || (tp == tl && delP);
      if (!takeTheirs) {
        run.keptMine++;
        return;
      }
      await _update(spec, key, {
        for (final e in incoming.entries)
          if (e.key != spec.key && !_localOnly(spec, incoming, e.key)) e.key: e.value,
      });
      delP ? run.deleted++ : run.updated++;
      run.touch(spec.name, incoming);
      await _storeBase(run.peer, spec.name, key, _baseOf(spec, incoming));
      await _autoResolve(run.peer, spec.name, key, _fieldsOf(spec, incoming), run.now);
      return;
    }

    final base = await _base(run.peer, spec.name, key);
    final window = conflictWindow.inSeconds;
    final merged = <String, Object?>{};
    final conflictFields = <String>{};
    var tookTheirs = false;
    var keptMineFree = false; // kept this device's value for a reason other than a conflict
    for (final f in _fieldsOf(spec, incoming)) {
      final m = local[f];
      final t = incoming[f];
      if (_eq(m, t)) continue;
      if (base != null && base.containsKey(f)) {
        final b = base[f];
        if (_eq(t, b)) {
          keptMineFree = true; // only this device changed it
          continue;
        }
        if (_eq(m, b)) {
          merged[f] = t; // only the peer changed it
          tookTheirs = true;
          continue;
        }
      }
      // Both changed it, or there is no record of the last version.
      if ((tl - tp).abs() <= window) {
        conflictFields.add(f);
        await _recordConflict(run, spec, key, f, m, t, tl, tp);
        continue;
      }
      if (tp > tl) {
        merged[f] = t;
        tookTheirs = true;
      } else {
        keptMineFree = true;
      }
    }
    if (merged.isNotEmpty) {
      // A mix of both sides is a version the peer has not seen: stamp it now so it
      // goes back. Taking only the peer's values keeps the peer's time.
      merged['updated_at'] = (tookTheirs && keptMineFree) ? run.now : tp;
      await _update(spec, key, merged);
      run.updated++;
      run.touch(spec.name, {...local, ...merged});
    } else if (conflictFields.isNotEmpty || keptMineFree) {
      run.keptMine++;
    }
    final result = {...local, ...merged};
    await _storeBase(run.peer, spec.name, key, _baseOf(spec, result), keepOldFor: conflictFields, oldBase: base);
    await _autoResolve(run.peer, spec.name, key, [
      for (final f in _fieldsOf(spec, incoming))
        if (_eq(result[f], incoming[f])) f,
    ], run.now);
  }

  /// Columns that stay on this device: the display order of the built-in place
  /// categories. Each phone and PC seeds them in its own order, and a restore
  /// can change it, so it must never be compared, merged or raised as a conflict.
  /// A category the owner added syncs its order as usual.
  bool _localOnly(SyncTableSpec spec, SyncRow row, String column) =>
      spec.name == 'place_categories' && column == 'sort' && (row['built_in'] == 1 || row['built_in'] == true);

  Iterable<String> _fieldsOf(SyncTableSpec spec, SyncRow row) =>
      row.keys.where((c) => c != spec.key && !metaColumns.contains(c) && !_localOnly(spec, row, c));

  // ----------------------------------------------------------------- twins

  Future<SyncRow?> _findTwin(SyncTableSpec spec, SyncRow row, String key) async {
    final live = row['deleted_at'] == null;
    final String sql;
    final List<Variable> vars;
    switch (spec.name) {
      case 'companies':
        if (!live) return null;
        sql = 'SELECT * FROM companies WHERE name_norm = ? AND deleted_at IS NULL AND uuid != ? LIMIT 1';
        vars = [Variable.withString('${row['name_norm']}'), Variable.withString(key)];
      case 'tags':
        if (!live) return null;
        sql = 'SELECT * FROM tags WHERE lower(name) = lower(?) AND deleted_at IS NULL AND uuid != ? LIMIT 1';
        vars = [Variable.withString('${row['name']}'), Variable.withString(key)];
      case 'place_categories':
        if (!live) return null;
        sql = 'SELECT * FROM place_categories WHERE lower(label) = lower(?) AND deleted_at IS NULL AND id != ? LIMIT 1';
        vars = [Variable.withString('${row['label']}'), Variable.withString(key)];
      case 'person_tags':
        sql = 'SELECT * FROM person_tags WHERE person_id = ? AND tag_id = ? AND uuid != ? LIMIT 1';
        vars = [
          Variable.withString('${row['person_id']}'),
          Variable.withString('${row['tag_id']}'),
          Variable.withString(key),
        ];
      case 'not_duplicates':
        sql = 'SELECT * FROM not_duplicates WHERE pair_key = ? AND uuid != ? LIMIT 1';
        vars = [Variable.withString('${row['pair_key']}'), Variable.withString(key)];
      default:
        return null;
    }
    final r = await db.customSelect(sql, variables: vars).getSingleOrNull();
    return r == null ? null : Map<String, Object?>.of(r.data);
  }

  /// Which of two same-named rows stays: a built-in category first, otherwise
  /// the smaller key. Both devices pick the same one, so they agree.
  String _winner(SyncTableSpec spec, SyncRow a, SyncRow b) {
    final ka = a[spec.key] as String;
    final kb = b[spec.key] as String;
    if (spec.name == 'place_categories') {
      final ba = a['built_in'] == 1;
      final bb = b['built_in'] == 1;
      if (ba != bb) return ba ? ka : kb;
    }
    return ka.compareTo(kb) <= 0 ? ka : kb;
  }

  /// Folds a local duplicate into [winnerKey]: rows that pointed at it point at
  /// the winner, and it goes (tombstoned, or removed where a UNIQUE constraint
  /// would block a tombstone).
  Future<void> _foldInto(
    SyncTableSpec spec, {
    required SyncRow loser,
    required String winnerKey,
    required _Run run,
  }) async {
    final loserKey = loser[spec.key] as String;
    run.merged++;
    if (uniqueNaturalKey.contains(spec.name)) {
      await db.customStatement('DELETE FROM ${spec.name} WHERE ${spec.key} = ?', [loserKey]);
      run.touch(spec.name, loser);
      return;
    }
    for (final child in syncTables) {
      for (final e in child.refs.entries) {
        if (e.value != spec.name) continue;
        if (child.name == 'person_tags' && e.key == 'tag_id') {
          await db.customStatement(
            'DELETE FROM person_tags WHERE tag_id = ? AND person_id IN (SELECT person_id FROM person_tags WHERE tag_id = ?)',
            [loserKey, winnerKey],
          );
        }
        await db.customStatement('UPDATE ${child.name} SET ${e.key} = ?, updated_at = ? WHERE ${e.key} = ?', [
          winnerKey,
          run.now,
          loserKey,
        ]);
        run.touchedTables.add(child.name);
      }
    }
    await db.customStatement('UPDATE ${spec.name} SET deleted_at = ?, updated_at = ? WHERE ${spec.key} = ?', [
      run.now,
      run.now,
      loserKey,
    ]);
    run.touch(spec.name, loser);
  }

  // ------------------------------------------------------------- row access

  Future<SyncRow?> _row(SyncTableSpec spec, String key) async {
    final r = await db
        .customSelect('SELECT * FROM ${spec.name} WHERE ${spec.key} = ?', variables: [Variable.withString(key)])
        .getSingleOrNull();
    return r == null ? null : Map<String, Object?>.of(r.data);
  }

  Future<bool> _parentsExist(SyncTableSpec spec, SyncRow row) async {
    if (spec.name == 'people') return true; // its links are loose: no foreign keys
    for (final e in spec.refs.entries) {
      final v = row[e.key];
      if (v is! String) continue;
      final parent = specOf(e.value);
      final r = await db
          .customSelect('SELECT 1 FROM ${parent.name} WHERE ${parent.key} = ?', variables: [Variable.withString(v)])
          .get();
      if (r.isEmpty) return false;
    }
    return true;
  }

  Future<void> _insert(SyncTableSpec spec, SyncRow row) async {
    final cols = row.keys.toList();
    await db.customStatement(
      'INSERT INTO ${spec.name} (${cols.join(', ')}) VALUES (${List.filled(cols.length, '?').join(', ')})',
      [for (final c in cols) row[c]],
    );
  }

  Future<void> _update(SyncTableSpec spec, String key, Map<String, Object?> values) async {
    final cols = values.keys.toList();
    if (cols.isEmpty) return;
    await db.customStatement(
      'UPDATE ${spec.name} SET ${[for (final c in cols) '$c = ?'].join(', ')} WHERE ${spec.key} = ?',
      [for (final c in cols) values[c], key],
    );
  }

  bool _eq(Object? a, Object? b) => a == b;

  // ----------------------------------------------------------- base and conflicts

  /// The row without bookkeeping columns, as kept in sync_base.
  Map<String, Object?> _baseOf(SyncTableSpec spec, SyncRow row) => {
    for (final e in row.entries)
      if (e.key != spec.key && !metaColumns.contains(e.key) && !_localOnly(spec, row, e.key)) e.key: e.value,
  };

  Future<Map<String, Object?>?> _base(String peerId, String table, String key) async {
    final r = await db
        .customSelect(
          'SELECT json FROM sync_base WHERE peer_id = ? AND table_name = ? AND row_key = ?',
          variables: [Variable.withString(peerId), Variable.withString(table), Variable.withString(key)],
        )
        .getSingleOrNull();
    return r == null ? null : (jsonDecode(r.read<String>('json')) as Map).cast<String, Object?>();
  }

  Future<void> _storeBase(
    String peerId,
    String table,
    String key,
    Map<String, Object?> json, {
    Set<String> keepOldFor = const {},
    Map<String, Object?>? oldBase,
  }) async {
    final out = Map<String, Object?>.of(json);
    if (keepOldFor.isNotEmpty) {
      final old = oldBase ?? await _base(peerId, table, key);
      for (final f in keepOldFor) {
        if (old != null && old.containsKey(f)) {
          out[f] = old[f];
        } else {
          out.remove(f); // unknown: the next merge treats it as changed on both sides
        }
      }
    }
    await db.customStatement(
      'INSERT OR REPLACE INTO sync_base (peer_id, table_name, row_key, json) VALUES (?, ?, ?, ?)',
      [peerId, table, key, jsonEncode(out)],
    );
  }

  Future<Map<String, Set<String>>> _openConflictFields(String peerId) async {
    final out = <String, Set<String>>{};
    for (final r
        in await db
            .customSelect(
              'SELECT table_name, row_key, field FROM sync_conflicts WHERE peer_id = ? AND resolved_at IS NULL',
              variables: [Variable.withString(peerId)],
            )
            .get()) {
      (out['${r.read<String>('table_name')}|${r.read<String>('row_key')}'] ??= {}).add(r.read<String>('field'));
    }
    return out;
  }

  Future<void> _recordConflict(
    _Run run,
    SyncTableSpec spec,
    String key,
    String field,
    Object? mine,
    Object? theirs,
    int tl,
    int tp,
  ) async {
    final existing = await db
        .customSelect(
          'SELECT id FROM sync_conflicts WHERE peer_id = ? AND table_name = ? AND row_key = ? AND field = ? AND resolved_at IS NULL',
          variables: [
            Variable.withString(run.peer),
            Variable.withString(spec.name),
            Variable.withString(key),
            Variable.withString(field),
          ],
        )
        .getSingleOrNull();
    final id = existing?.read<String>('id') ?? uuidGen.v4();
    if (existing == null) {
      await db.customStatement(
        'INSERT INTO sync_conflicts (id, peer_id, table_name, row_key, field, mine_json, theirs_json, mine_updated_at, theirs_updated_at, detected_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, run.peer, spec.name, key, field, jsonEncode(mine), jsonEncode(theirs), tl, tp, run.now],
      );
    } else {
      await db.customStatement(
        'UPDATE sync_conflicts SET mine_json = ?, theirs_json = ?, mine_updated_at = ?, theirs_updated_at = ? WHERE id = ?',
        [jsonEncode(mine), jsonEncode(theirs), tl, tp, id],
      );
    }
    run.conflicts.add(
      SyncConflict(
        id: id,
        peerId: run.peer,
        table: spec.name,
        rowKey: key,
        field: field,
        mine: mine,
        theirs: theirs,
        mineUpdatedAt: tl,
        theirsUpdatedAt: tp,
        detectedAt: run.now,
      ),
    );
    run.touchedTables.add('sync_conflicts');
  }

  /// When the two devices end up with the same value, the conflict is over.
  Future<void> _autoResolve(String peerId, String table, String key, Iterable<String> fields, int now) async {
    for (final f in fields) {
      await db.customStatement(
        "UPDATE sync_conflicts SET resolved_at = ?, resolution = 'sync' "
        'WHERE peer_id = ? AND table_name = ? AND row_key = ? AND field = ? AND resolved_at IS NULL',
        [now, peerId, table, key, f],
      );
    }
  }

  // ------------------------------------------------------- conflict resolution

  Future<List<SyncConflict>> conflicts({bool openOnly = true}) async => [
    for (final r
        in await db
            .customSelect(
              'SELECT * FROM sync_conflicts ${openOnly ? 'WHERE resolved_at IS NULL ' : ''}ORDER BY detected_at, id',
            )
            .get())
      _conflictOf(r.data),
  ];

  Future<int> openConflictCount() async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM sync_conflicts WHERE resolved_at IS NULL').getSingle())
          .read<int>('n');

  SyncConflict _conflictOf(Map<String, Object?> d) => SyncConflict(
    id: d['id'] as String,
    peerId: d['peer_id'] as String,
    table: d['table_name'] as String,
    rowKey: d['row_key'] as String,
    field: d['field'] as String,
    mine: jsonDecode(d['mine_json'] as String),
    theirs: jsonDecode(d['theirs_json'] as String),
    mineUpdatedAt: d['mine_updated_at'] as int,
    theirsUpdatedAt: d['theirs_updated_at'] as int,
    detectedAt: d['detected_at'] as int,
    resolvedAt: d['resolved_at'] as int?,
    resolution: d['resolution'] as String?,
  );

  /// Keep this device's value: it goes to the peer as the newer version.
  Future<void> resolveMine(String conflictId) => _resolve(conflictId, mine: true);

  /// Take the peer's value.
  Future<void> resolveTheirs(String conflictId) => _resolve(conflictId, mine: false);

  Future<void> _resolve(String id, {required bool mine}) async {
    final r = await db
        .customSelect('SELECT * FROM sync_conflicts WHERE id = ?', variables: [Variable.withString(id)])
        .getSingleOrNull();
    if (r == null) return;
    final c = _conflictOf(r.data);
    if (!c.isOpen) return;
    final spec = specOf(c.table);
    final now = _now();
    await db.transaction(() async {
      final local = await _row(spec, c.rowKey);
      if (local != null) {
        // Stamp the row now either way: keeping mine sends it back as the newer
        // version; taking theirs records the choice so it reaches the peer too.
        await _update(spec, c.rowKey, {if (!mine) c.field: c.theirs, 'updated_at': now});
      }
      // Remember the peer's value as the last common one, so its older row does
      // not raise the same conflict again.
      final base = await _base(c.peerId, c.table, c.rowKey) ?? <String, Object?>{};
      base[c.field] = c.theirs;
      await db.customStatement(
        'INSERT OR REPLACE INTO sync_base (peer_id, table_name, row_key, json) VALUES (?, ?, ?, ?)',
        [c.peerId, c.table, c.rowKey, jsonEncode(base)],
      );
      await db.customStatement('UPDATE sync_conflicts SET resolved_at = ?, resolution = ? WHERE id = ?', [
        now,
        mine ? 'mine' : 'theirs',
        id,
      ]);
    });
    db.markTablesUpdated([
      for (final t in db.allTables)
        if (t.actualTableName == c.table) t,
    ]);
    if (c.table == 'people') await reindexPeople?.call({c.rowKey});
  }
}

class _Cursor {
  final int table;
  final int updatedAt;
  final String key;
  const _Cursor(this.table, this.updatedAt, this.key);

  bool get hasPosition => key.isNotEmpty;

  static _Cursor parse(String? s) {
    if (s == null || s.isEmpty || s.startsWith('piece:')) return const _Cursor(0, 0, '');
    final p = s.split(':');
    return _Cursor(int.parse(p[0]), int.parse(p[1]), p.sublist(2).join(':'));
  }

  String encode() => '$table:$updatedAt:$key';
}

/// State of one apply().
class _Run {
  final String peer;
  final int offset;
  final int now;
  int inserted = 0, updated = 0, deleted = 0, keptMine = 0, merged = 0, orphans = 0;
  final List<SyncConflict> conflicts = [];
  final Set<String> people = {};
  final Set<String> touchedTables = {};
  final Map<String, Map<String, String>> remap = {};

  _Run(this.peer, this.offset, this.now);

  void touch(String table, Map<String, Object?> row) {
    touchedTables.add(table);
    if (table == 'people') {
      people.add(row['uuid'] as String);
    } else if (row['person_id'] is String) {
      people.add(row['person_id'] as String);
    }
  }
}
