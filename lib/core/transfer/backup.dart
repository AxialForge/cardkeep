import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sq;

import '../contacts/purge.dart';
import '../db/database.dart';

const dbFileName = 'card_organizer.sqlite';

/// Limits for a backup file (audit MOB-SEC-0102): far above any real library,
/// low enough that a hostile zip cannot fill the phone.
const maxBackupBytes = 1024 * 1024 * 1024;
const maxUnpackedBytes = 2 * 1024 * 1024 * 1024;

/// How long the pre-restore fallback copy is kept (audit MOB-PRV-0003).
const fallbackKeep = Duration(days: 30);

class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => message;
}

/// What a backup says about itself (manifest.json).
class BackupInfo {
  final int schema, people, cards;
  final String appVersion;
  final DateTime created;
  const BackupInfo(this.schema, this.appVersion, this.created, this.people, this.cards);
}

/// Backup and restore (roadmap S13.8-S13.10). A backup is one zip: a
/// consistent copy of the database (VACUUM INTO), every card image, and a
/// manifest with the schema version and a sha256 per file.
class Backups {
  final AppDatabase db;
  final Directory docs; // app documents: the database and cards/ live here
  final DateTime Function() now;
  Backups(this.db, this.docs, {DateTime Function()? clock}) : now = clock ?? DateTime.now;

  Directory get autoDir => Directory(p.join(docs.path, 'backups'));

  Future<Uint8List> create({String appVersion = ''}) async {
    final tmp = File(p.join(Directory.systemTemp.path, 'ck_backup_${now().microsecondsSinceEpoch}.sqlite'));
    if (tmp.existsSync()) tmp.deleteSync();
    final files = <String, List<int>>{};
    final Set<String> keep;
    try {
      await db.customStatement('VACUUM INTO ?', [tmp.path]);
      // Deleted contacts never travel in a backup (audit MOB-PRV-0002): purge
      // them from the copy, then take only the images the copy still uses.
      final copy = AppDatabase(NativeDatabase(tmp));
      try {
        await purgeDeleted(copy, before: now().add(const Duration(days: 1)));
        keep = await referencedImages(copy);
        await copy.customStatement('VACUUM');
      } finally {
        await copy.close();
      }
      files[dbFileName] = await tmp.readAsBytes();
    } finally {
      if (tmp.existsSync()) await tmp.delete();
    }
    final cards = Directory(p.join(docs.path, 'cards'));
    if (cards.existsSync()) {
      for (final f in cards.listSync(recursive: true).whereType<File>()) {
        final rel = p.relative(f.path, from: docs.path).replaceAll(r'\', '/');
        if (rel.startsWith('cards/pending/')) continue; // half-processed captures
        if (!keep.contains(p.basenameWithoutExtension(f.path))) continue;
        files[rel] = await f.readAsBytes();
      }
    }
    final counts = (await db
        .customSelect(
          'SELECT (SELECT COUNT(*) FROM people WHERE deleted_at IS NULL) AS p, '
          '(SELECT COUNT(*) FROM cards WHERE deleted_at IS NULL) AS c',
        )
        .getSingle());
    final manifest = {
      'app': 'CardKeep',
      'appVersion': appVersion,
      'schema': db.schemaVersion,
      'created': now().toIso8601String(),
      'people': counts.read<int>('p'),
      'cards': counts.read<int>('c'),
      'files': {for (final e in files.entries) e.key: sha256.convert(e.value).toString()},
    };
    final zip = Archive()
      ..add(ArchiveFile.string('manifest.json', const JsonEncoder.withIndent(' ').convert(manifest)));
    for (final e in files.entries) {
      zip.add(ArchiveFile.bytes(e.key, e.value));
    }
    return Uint8List.fromList(ZipEncoder().encode(zip));
  }

  /// Checks a backup before anything is replaced (S13.9): it must be
  /// CardKeep's, not from a newer app, and every file must match its hash.
  BackupInfo check(Uint8List zipBytes) {
    if (zipBytes.length > maxBackupBytes) throw const BackupException('This backup is too large to restore.');
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(zipBytes);
    } catch (_) {
      throw const BackupException('This is not a CardKeep backup (not a zip file).');
    }
    final m = zip.findFile('manifest.json');
    if (m == null) throw const BackupException('This is not a CardKeep backup (no manifest).');
    final Map<String, Object?> j;
    try {
      j = (jsonDecode(utf8.decode(m.content)) as Map).cast<String, Object?>();
    } catch (_) {
      throw const BackupException('The backup is damaged (unreadable manifest).');
    }
    if (j['app'] != 'CardKeep') throw const BackupException('This is not a CardKeep backup.');
    final schema = (j['schema'] as num?)?.toInt() ?? 0;
    if (schema > db.schemaVersion) {
      throw const BackupException('This backup is from a newer CardKeep. Update CardKeep first, then restore.');
    }
    final hashes = ((j['files'] as Map?) ?? const {}).cast<String, Object?>();
    if (!hashes.containsKey(dbFileName)) throw const BackupException('The backup has no database.');
    // Sizes are checked before anything is unpacked.
    var unpacked = 0;
    for (final f in zip.files) {
      if (f.isFile) unpacked += f.size;
    }
    if (unpacked > maxUnpackedBytes) throw const BackupException('This backup is too large to restore.');
    for (final e in hashes.entries) {
      final f = zip.findFile(e.key);
      if (f == null || sha256.convert(f.content).toString() != e.value) {
        throw BackupException('The backup is damaged (${e.key} does not match).');
      }
    }
    return BackupInfo(
      schema,
      '${j['appVersion'] ?? ''}',
      DateTime.tryParse('${j['created']}') ?? DateTime(2000),
      (j['people'] as num?)?.toInt() ?? 0,
      (j['cards'] as num?)?.toInt() ?? 0,
    );
  }

  /// Unpacks a checked backup into restore_pending/. The swap happens on the
  /// next start, before the database opens ([applyPendingRestore]).
  Future<void> stage(Uint8List zipBytes) async {
    check(zipBytes);
    final zip = ZipDecoder().decodeBytes(zipBytes);
    final listed = ((jsonDecode(utf8.decode(zip.findFile('manifest.json')!.content)) as Map)['files'] as Map).keys
        .toSet();
    final dir = Directory(p.join(docs.path, 'restore_pending'));
    if (dir.existsSync()) await dir.delete(recursive: true);
    for (final f in zip.files) {
      // Only files the manifest lists (and so were hash-checked) are staged.
      if (!f.isFile || !listed.contains(f.name)) continue;
      final out = File(p.normalize(p.join(dir.path, f.name)));
      if (!p.isWithin(dir.path, out.path)) continue; // no ../ escapes
      out.parent.createSync(recursive: true);
      await out.writeAsBytes(f.content, flush: true);
    }
    if (!_integrityOk(File(p.join(dir.path, dbFileName)))) {
      await dir.delete(recursive: true);
      throw const BackupException('The backup is damaged (the database does not pass its check).');
    }
    await File(p.join(dir.path, '.ready')).writeAsString(now().toIso8601String(), flush: true);
  }

  // ------------------------------------------------------- fallback copy

  /// The data from before the last restore (audit MOB-REL-0003, MOB-PRV-0003).
  Directory get fallbackDir => Directory(p.join(docs.path, 'before_restore'));

  bool get hasFallback => File(p.join(fallbackDir.path, dbFileName)).existsSync();

  /// When the fallback copy was made, and how much space it takes.
  DateTime? fallbackDate() => hasFallback ? fallbackMade(docs) : null;
  int fallbackBytes() => !fallbackDir.existsSync()
      ? 0
      : fallbackDir.listSync(recursive: true).whereType<File>().fold(0, (n, f) => n + f.lengthSync());

  Future<void> discardFallback() async {
    if (fallbackDir.existsSync()) await fallbackDir.delete(recursive: true);
  }

  /// Puts the fallback copy back: it is staged like a backup (moved, not
  /// copied), so on the next start the current data and the fallback swap.
  Future<void> stageFallback() async {
    if (!hasFallback) throw const BackupException('There is no earlier copy to go back to.');
    final dir = Directory(p.join(docs.path, 'restore_pending'));
    if (dir.existsSync()) await dir.delete(recursive: true);
    await fallbackDir.rename(dir.path);
    final made = File(p.join(dir.path, '.made'));
    if (made.existsSync()) await made.delete();
    await File(p.join(dir.path, '.ready')).writeAsString(now().toIso8601String(), flush: true);
  }

  // ------------------------------------------------------------ automatic

  /// Weekly backup when the app is opened and one is due (S13.10); keeps the
  /// newest [keep]. Returns the file written, or null when not due.
  Future<File?> autoBackupIfDue({
    int keep = 4,
    Duration every = const Duration(days: 7),
    String appVersion = '',
  }) async {
    final last = listAuto().firstOrNull;
    if (last != null && now().difference(last.statSync().modified) < every) return null;
    autoDir.createSync(recursive: true);
    final t = now();
    final f = File(
      p.join(
        autoDir.path,
        'CardKeep backup ${t.year}-${_pad(t.month)}-${_pad(t.day)} ${_pad(t.hour)}${_pad(t.minute)}.zip',
      ),
    );
    await f.writeAsBytes(await create(appVersion: appVersion), flush: true);
    for (final old in listAuto().skip(keep)) {
      old.deleteSync();
    }
    return f;
  }

  /// Automatic backups, newest first.
  List<File> listAuto() {
    if (!autoDir.existsSync()) return const [];
    return autoDir.listSync().whereType<File>().where((f) => f.path.endsWith('.zip')).toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}

/// What happened to a pending restore at start.
enum RestoreOutcome { none, restored, refused, failed }

/// Set by main() so the app can say what happened (audit MOB-REL-0003).
RestoreOutcome lastRestoreOutcome = RestoreOutcome.none;

/// Runs in main() before the database opens: swaps the staged backup in and
/// keeps the current data in before_restore/ as the fallback copy.
///
/// Crash-safe (audit MOB-REL-0001). The phase is written to
/// restore_pending/.phase before each step, and every step only moves what is
/// still in its old place, so a kill at any point resumes on the next start.
/// The previous fallback copy is replaced only after the new data is fully in
/// place, and at no point is the only copy of anything deleted. [onStep] is
/// for tests (simulate a kill by throwing). Older backups are migrated by the
/// normal database upgrade.
Future<RestoreOutcome> applyPendingRestore(Directory docs, {void Function(String step)? onStep}) async {
  final staged = Directory(p.join(docs.path, 'restore_pending'));
  if (!File(p.join(staged.path, '.ready')).existsSync()) {
    // Nothing to restore: an old fallback copy goes after [fallbackKeep].
    final keep = Directory(p.join(docs.path, 'before_restore'));
    final made = fallbackMade(docs);
    if (made != null && DateTime.now().difference(made) > fallbackKeep) await keep.delete(recursive: true);
    return RestoreOutcome.none;
  }
  final phaseFile = File(p.join(staged.path, '.phase'));
  final keepNew = Directory(p.join(docs.path, 'before_restore.new'));
  final keep = Directory(p.join(docs.path, 'before_restore'));
  final live = [dbFileName, '$dbFileName-wal', '$dbFileName-shm'];
  var phase = phaseFile.existsSync() ? phaseFile.readAsStringSync().trim() : '';

  Future<void> setPhase(String v) async {
    await phaseFile.writeAsString(v, flush: true);
    phase = v;
    onStep?.call(v);
  }

  // Never overwrite: a destination that exists already holds the real copy (from
  // an earlier, interrupted run).
  Future<void> move(FileSystemEntity from, String to) async {
    if (!from.existsSync() || FileSystemEntity.typeSync(to) != FileSystemEntityType.notFound) return;
    Directory(p.dirname(to)).createSync(recursive: true);
    await from.rename(to);
    onStep?.call('moved ${p.basename(from.path)}');
  }

  if (phase.isEmpty) {
    // A damaged or incomplete stage is refused before anything is touched.
    final db = File(p.join(staged.path, dbFileName));
    if (!db.existsSync() || !_isSqlite(db)) {
      await staged.delete(recursive: true);
      return RestoreOutcome.refused;
    }
    await setPhase('old');
  }
  if (phase == 'old') {
    // Current data aside, into a NEW fallback folder (the old one is kept for now).
    for (final name in live) {
      await move(File(p.join(docs.path, name)), p.join(keepNew.path, name));
    }
    await move(Directory(p.join(docs.path, 'cards')), p.join(keepNew.path, 'cards'));
    await setPhase('new');
  }
  if (phase == 'new') {
    // A database here now can only be an empty one the app created after an
    // interrupted swap (the real one is in before_restore.new): clear it first.
    if (File(p.join(staged.path, dbFileName)).existsSync()) {
      for (final name in live) {
        final f = File(p.join(docs.path, name));
        if (f.existsSync()) await f.delete();
      }
    }
    // Likewise a cards/ folder made after an interrupted swap: set aside, not deleted.
    final strayCards = Directory(p.join(docs.path, 'cards'));
    if (Directory(p.join(staged.path, 'cards')).existsSync() && strayCards.existsSync()) {
      await strayCards.rename(
        p.join(keepNew.path, 'cards-after-interrupted-restore-${DateTime.now().millisecondsSinceEpoch}'),
      );
    }
    await move(File(p.join(staged.path, dbFileName)), p.join(docs.path, dbFileName));
    await move(Directory(p.join(staged.path, 'cards')), p.join(docs.path, 'cards'));
    await setPhase('keep');
  }
  if (phase == 'keep') {
    // Only now is the previous fallback copy replaced.
    if (keepNew.existsSync()) {
      if (keep.existsSync()) await keep.delete(recursive: true);
      await File(p.join(keepNew.path, '.made')).writeAsString(DateTime.now().toIso8601String(), flush: true);
      await keepNew.rename(keep.path);
    }
    await setPhase('done');
  }
  await staged.delete(recursive: true);
  return RestoreOutcome.restored;
}

/// When the before_restore/ copy was made (its .made marker, else the database's date).
DateTime? fallbackMade(Directory docs) {
  final keep = p.join(docs.path, 'before_restore');
  final marker = File(p.join(keep, '.made'));
  if (marker.existsSync()) return DateTime.tryParse(marker.readAsStringSync().trim());
  final db = File(p.join(keep, dbFileName));
  return db.existsSync() ? db.lastModifiedSync() : null;
}

/// SQLite's own check of the staged database before it replaces the live one.
bool _integrityOk(File f) {
  if (!f.existsSync() || !_isSqlite(f)) return false;
  try {
    final db = sq.sqlite3.open(f.path, mode: sq.OpenMode.readOnly);
    try {
      final r = db.select('PRAGMA integrity_check');
      return r.length == 1 && r.first.values.first == 'ok';
    } finally {
      db.close();
    }
  } catch (_) {
    return false;
  }
}

bool _isSqlite(File f) {
  try {
    final raf = f.openSync();
    final head = raf.readSync(16);
    raf.closeSync();
    return String.fromCharCodes(head.take(15)) == 'SQLite format 3';
  } catch (_) {
    return false;
  }
}
