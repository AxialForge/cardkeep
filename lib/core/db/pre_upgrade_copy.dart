/// A copy of the database as it was just before a schema upgrade.
///
/// On the owner's phone a database upgrade once left the library looking empty
/// (0 people, with the review queue and ~180 MB of photos still there) and only
/// a backup brought it back. The cause was never proven, so before SQLite is
/// asked to upgrade a file, a byte-for-byte copy of it (and its -wal and -shm
/// files) is kept in `before_upgrade/<from>-<time>/`. The newest two are kept,
/// and any older than 14 days go. Settings has "Go back to it".
library;

import 'dart:io';

import 'package:path/path.dart' as p;

const beforeUpgradeName = 'before_upgrade';
const upgradeCopyKeep = 2;
const upgradeCopyMaxAge = Duration(days: 14);

const _db = 'card_organizer.sqlite';
const _files = [_db, '$_db-wal', '$_db-shm'];

/// One kept copy.
class UpgradeCopy {
  final Directory dir;
  final int fromVersion;
  final DateTime made;
  final int bytes;
  const UpgradeCopy(this.dir, this.fromVersion, this.made, this.bytes);
}

Directory upgradeCopiesDir(Directory docs) => Directory(p.join(docs.path, beforeUpgradeName));

/// The schema version a database file says it has (PRAGMA user_version), or null
/// when there is no file or it is too short to tell. Read straight from the file
/// header (offset 60), so SQLite never opens it and neither the file nor its
/// -wal and -shm are touched. The header can lag behind the real value until
/// SQLite next checkpoints, but it is never ahead of it: at worst this makes one
/// extra, harmless copy, and it can never miss a database that needs upgrading.
int? readSchemaVersion(File file) {
  if (!file.existsSync() || file.lengthSync() < 100) return null;
  try {
    final raf = file.openSync();
    try {
      final h = raf.readSync(100);
      if (h.length < 64) return null;
      return (h[60] << 24) | (h[61] << 16) | (h[62] << 8) | h[63];
    } finally {
      raf.closeSync();
    }
  } catch (_) {
    return null;
  }
}

String _stamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
}

/// Copies the live database aside when it is older than [targetVersion], so the
/// upgrade about to run cannot cost anything. Returns the new copy, or null when
/// nothing needed copying (no database yet, already current, or unreadable).
/// Never overwrites. Also prunes old copies.
Future<UpgradeCopy?> copyBeforeUpgrade(Directory docs, {required int targetVersion, DateTime? now}) async {
  final t = now ?? DateTime.now();
  UpgradeCopy? made;
  final live = File(p.join(docs.path, _db));
  final from = readSchemaVersion(live);
  // user_version 0 is a database that was never set up.
  if (from != null && from > 0 && from < targetVersion) {
    final root = upgradeCopiesDir(docs);
    var dir = Directory(p.join(root.path, 'v$from-${_stamp(t)}'));
    for (var i = 2; dir.existsSync(); i++) {
      dir = Directory(p.join(root.path, 'v$from-${_stamp(t)}-$i'));
    }
    dir.createSync(recursive: true);
    var bytes = 0;
    for (final name in _files) {
      final f = File(p.join(docs.path, name));
      if (!f.existsSync()) continue;
      await f.copy(p.join(dir.path, name));
      bytes += f.lengthSync();
    }
    // The marker goes last: a folder without it is an interrupted copy.
    await File(p.join(dir.path, '.made')).writeAsString(t.toIso8601String(), flush: true);
    made = UpgradeCopy(dir, from, t, bytes);
  }
  pruneUpgradeCopies(docs, now: t);
  return made;
}

/// The copies on this phone, newest first. A folder without its `.made` marker
/// (an interrupted copy) is not listed.
List<UpgradeCopy> listUpgradeCopies(Directory docs) {
  final root = upgradeCopiesDir(docs);
  if (!root.existsSync()) return const [];
  final out = <UpgradeCopy>[];
  for (final d in root.listSync().whereType<Directory>()) {
    final marker = File(p.join(d.path, '.made'));
    if (!marker.existsSync()) continue;
    final made = DateTime.tryParse(marker.readAsStringSync().trim());
    final m = RegExp(r'^v(\d+)-').firstMatch(p.basename(d.path));
    if (made == null || m == null) continue;
    var bytes = 0;
    for (final name in _files) {
      final f = File(p.join(d.path, name));
      if (f.existsSync()) bytes += f.lengthSync();
    }
    out.add(UpgradeCopy(d, int.parse(m.group(1)!), made, bytes));
  }
  out.sort((a, b) => b.made.compareTo(a.made));
  return out;
}

/// Keeps the newest [upgradeCopyKeep] and drops anything older than 14 days,
/// plus interrupted copies.
void pruneUpgradeCopies(Directory docs, {DateTime? now}) {
  final t = now ?? DateTime.now();
  final root = upgradeCopiesDir(docs);
  if (!root.existsSync()) return;
  final listed = listUpgradeCopies(docs);
  final keepDirs = <String>{};
  for (final (i, c) in listed.indexed) {
    if (i < upgradeCopyKeep && t.difference(c.made) <= upgradeCopyMaxAge) keepDirs.add(c.dir.path);
  }
  for (final d in root.listSync().whereType<Directory>()) {
    if (keepDirs.contains(d.path)) continue;
    try {
      d.deleteSync(recursive: true);
    } catch (_) {
      // Tried again at the next start.
    }
  }
}

/// Stages [copy] as a restore: copied (not moved, so the copy stays) into
/// restore_pending/ with a `.keepcards` marker (the pictures in cards/ are not
/// part of it and stay where they are). The swap happens at the next start, in
/// applyPendingRestore, which keeps the current data as the fallback copy.
Future<void> stageUpgradeCopyOf(Directory docs, UpgradeCopy copy, {DateTime? now}) async {
  final dir = Directory(p.join(docs.path, 'restore_pending'));
  if (dir.existsSync()) await dir.delete(recursive: true);
  dir.createSync(recursive: true);
  for (final name in _files) {
    final f = File(p.join(copy.dir.path, name));
    if (f.existsSync()) await f.copy(p.join(dir.path, name));
  }
  await File(p.join(dir.path, '.keepcards')).writeAsString('1', flush: true);
  await File(p.join(dir.path, '.ready')).writeAsString((now ?? DateTime.now()).toIso8601String(), flush: true);
}

Future<void> discardUpgradeCopies(Directory docs) async {
  final root = upgradeCopiesDir(docs);
  if (root.existsSync()) await root.delete(recursive: true);
}
