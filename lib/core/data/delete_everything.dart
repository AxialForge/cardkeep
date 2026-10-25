import 'dart:io';

import 'package:path/path.dart' as p;

import '../db/database.dart';

/// What "Delete everything" removed, for the message afterwards.
class DeleteEverythingResult {
  final int people, files;
  const DeleteEverythingResult(this.people, this.files);
}

/// Tables that hold settings rather than the person's own data. They survive
/// "Delete everything" unless the person also chooses to reset settings.
const _settingsTables = {'app_settings', 'place_categories'};

/// Removes every contact, company, tag, event, card and photo, the review queue,
/// and the backups and fallback copies CardKeep keeps on the phone (S15.7).
///
/// [docs] is the app's documents folder. Settings stay unless [resetSettings] is
/// true. The database file itself is kept (and emptied) so the app keeps working.
/// A backup the person saved elsewhere with "Save to" is theirs and is never touched.
Future<DeleteEverythingResult> deleteEverything(AppDatabase db, Directory docs, {bool resetSettings = false}) async {
  final people = (await db.customSelect('SELECT COUNT(*) AS n FROM people WHERE deleted_at IS NULL').getSingle())
      .read<int>('n');
  await db.transaction(() async {
    // Rows point at each other; check the links once everything is gone, not row by row.
    await db.customStatement('PRAGMA defer_foreign_keys = ON');
    for (final t in db.allTables) {
      final name = t.actualTableName;
      if (_settingsTables.contains(name) && !(resetSettings && name == 'app_settings')) continue;
      await db.customStatement('DELETE FROM "$name"');
    }
    await db.customStatement('DELETE FROM person_search');
  });
  var files = 0;
  for (final name in ['cards', 'backups', 'before_restore', 'before_restore.new', 'restore_pending']) {
    final d = Directory(p.join(docs.path, name));
    if (!d.existsSync()) continue;
    files += d.listSync(recursive: true).whereType<File>().length;
    try {
      await d.delete(recursive: true);
    } catch (_) {
      // A folder that cannot be removed is emptied by the next start's clean-up.
    }
  }
  return DeleteEverythingResult(people, files);
}
