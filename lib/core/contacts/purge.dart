/// Purging deleted contacts (audit MOB-PRV-0002). A delete is a tombstone so
/// it can be undone and, later, synced; after [retention] everything about the
/// person is removed: details, notes, tags, cards and their images. Only a
/// blank row (id + deleted_at) stays for sync.
library;

import 'dart:io';

import 'package:drift/drift.dart';

import '../db/database.dart';
import '../images/image_store.dart';

const retention = Duration(days: 7);

class PurgeResult {
  final int people, files;
  const PurgeResult(this.people, this.files);
}

/// Removes the data of people deleted before [before]. Returns how many people
/// were purged; unreferenced image files are removed when [store] is given.
Future<PurgeResult> purgeDeleted(AppDatabase db, {required DateTime before, ImageStore? store}) async {
  final cutoff = Variable.withDateTime(before);
  final ids = [
    for (final r
        in await db
            .customSelect(
              "SELECT uuid FROM people WHERE deleted_at IS NOT NULL AND deleted_at < ? AND display_name != ''",
              variables: [cutoff],
            )
            .get())
      r.read<String>('uuid'),
  ];
  await db.transaction(() async {
    for (final id in ids) {
      final v = [Variable.withString(id)];
      for (final sql in [
        'DELETE FROM contact_points WHERE person_id = ?',
        'DELETE FROM roles WHERE person_id = ?',
        'DELETE FROM person_tags WHERE person_id = ?',
        'DELETE FROM change_suggestions WHERE person_id = ?',
        'DELETE FROM cards WHERE person_id = ?',
        'DELETE FROM successions WHERE predecessor_person_id = ?',
        'UPDATE successions SET successor_person_id = NULL WHERE successor_person_id = ?',
        'UPDATE people SET introduced_by_person_id = NULL WHERE introduced_by_person_id = ?',
        "DELETE FROM not_duplicates WHERE pair_key LIKE '%' || ? || '%'",
        "UPDATE people SET first = '', middle = '', last = '', display_name = '', notes = '', hours = '', extras_json = '[]', "
            'logo_sha256 = NULL, lead_rating = NULL, followup_at = NULL, followup_done_at = NULL, met_event_id = NULL '
            'WHERE uuid = ?',
      ]) {
        await db.customUpdate(sql, variables: v, updates: {db.people});
      }
      await db.customStatement('DELETE FROM person_search WHERE person_id = ?', [id]);
    }
    // Cards removed from the review queue (tombstoned, images already deleted).
    await db.customUpdate(
      'DELETE FROM cards WHERE person_id IS NULL AND deleted_at IS NOT NULL AND deleted_at < ?',
      variables: [cutoff],
      updates: {db.cards},
    );
  });
  var files = 0;
  if (store != null) files = await removeUnreferencedImages(db, store);
  return PurgeResult(ids.length, files);
}

/// Every image hash still in use: cards that exist (saved or waiting in the
/// queue, including recently deleted ones that can still be undone) and logos.
Future<Set<String>> referencedImages(AppDatabase db) async {
  final rows = await db
      .customSelect(
        'SELECT front_sha256 AS h FROM cards UNION SELECT back_sha256 FROM cards WHERE back_sha256 IS NOT NULL '
        'UNION SELECT logo_sha256 FROM people WHERE logo_sha256 IS NOT NULL',
      )
      .get();
  return {for (final r in rows) ?r.readNullable<String>('h')};
}

/// Deletes image files no row refers to (card photos and logos).
Future<int> removeUnreferencedImages(AppDatabase db, ImageStore store) async {
  final keep = await referencedImages(db);
  var n = 0;
  for (final sub in ['original', 'rectified', 'thumb', 'logo']) {
    final dir = Directory('${store.root.path}${Platform.pathSeparator}$sub');
    if (!dir.existsSync()) continue;
    for (final f in dir.listSync().whereType<File>()) {
      final hash = f.uri.pathSegments.last.split('.').first;
      if (!keep.contains(hash)) {
        f.deleteSync();
        n++;
      }
    }
  }
  return n;
}
