import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/images/image_store.dart';
import 'package:card_organizer/core/transfer/backup.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory docs;
  late AppDatabase db;
  late Backups backups;

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('ck_harden');
    db = AppDatabase(NativeDatabase(File(p.join(docs.path, dbFileName))));
    await ContactsRepository(db).save(ContactDraft(first: 'Dana', last: 'Reyes'));
    backups = Backups(db, docs);
  });
  tearDown(() async {
    await db.close();
    await docs.delete(recursive: true);
  });

  Uint8List rezip(Uint8List zip, {Map<String, List<int>> add = const {}, Map<String, List<int>> replace = const {}}) {
    final a = ZipDecoder().decodeBytes(zip);
    final files = {for (final f in a.files) f.name: f.content as List<int>, ...add};
    final m = (jsonDecode(utf8.decode(files['manifest.json']!)) as Map).cast<String, Object?>();
    final hashes = (m['files'] as Map).cast<String, Object?>();
    replace.forEach((k, v) {
      files[k] = v;
      hashes[k] = sha256.convert(v).toString(); // a consistent but bad manifest
    });
    files['manifest.json'] = utf8.encode(jsonEncode(m));
    final out = Archive();
    files.forEach((k, v) => out.add(ArchiveFile.bytes(k, v)));
    return Uint8List.fromList(ZipEncoder().encode(out));
  }

  test('files the manifest does not list are not staged (MOB-SEC-0102)', () async {
    final zip = rezip(
      await backups.create(),
      add: {
        'cards/rectified/planted.jpg': [1, 2, 3],
      },
    );
    await backups.stage(zip);
    expect(File(p.join(docs.path, 'restore_pending', 'cards', 'rectified', 'planted.jpg')).existsSync(), isFalse);
    expect(File(p.join(docs.path, 'restore_pending', '.ready')).existsSync(), isTrue);
  });

  test('a database that fails its integrity check is refused before staging', () async {
    final good = await backups.create();
    final dbBytes = ZipDecoder().decodeBytes(good).findFile(dbFileName)!.content as List<int>;
    final broken = List<int>.of(dbBytes);
    for (var i = 4096; i < broken.length && i < 8192; i++) {
      broken[i] = 0xAB; // page 2 overwritten; the header still says SQLite
    }
    final zip = rezip(good, replace: {dbFileName: broken});
    await expectLater(backups.stage(zip), throwsA(isA<BackupException>()));
    expect(Directory(p.join(docs.path, 'restore_pending')).existsSync(), isFalse);
  });

  test('the fallback copy can be put back, discarded, and goes after 30 days (REL-0003, PRV-0003)', () async {
    // A restore leaves before_restore/.
    await backups.stage(await backups.create());
    await db.close();
    expect(await applyPendingRestore(docs), RestoreOutcome.restored);
    db = AppDatabase(NativeDatabase(File(p.join(docs.path, dbFileName))));
    backups = Backups(db, docs);
    expect(backups.hasFallback, isTrue);
    expect(backups.fallbackBytes(), greaterThan(0));

    // Going back: staged by moving it, swapped on the next start.
    await backups.stageFallback();
    expect(backups.hasFallback, isFalse);
    await db.close();
    expect(await applyPendingRestore(docs), RestoreOutcome.restored);
    db = AppDatabase(NativeDatabase(File(p.join(docs.path, dbFileName))));
    backups = Backups(db, docs);
    expect(backups.hasFallback, isTrue, reason: 'what was current is now the fallback');

    // Older than 30 days: removed at start.
    File(p.join(backups.fallbackDir.path, '.made'))
        .writeAsStringSync(DateTime.now().subtract(const Duration(days: 31)).toIso8601String());
    expect(await applyPendingRestore(docs), RestoreOutcome.none);
    expect(backups.hasFallback, isFalse);
  });

  test('a capture that keeps failing is set aside after 3 tries (MOB-REL-0005)', () async {
    final store = ImageStore(Directory(p.join(docs.path, 'cards')));
    final f = await store.savePending(Uint8List.fromList([1, 2, 3]));
    expect(await store.failedPending(f), isFalse);
    expect(store.orphanedPending().length, 1);
    expect(await store.failedPending(f), isFalse);
    expect(await store.failedPending(f), isTrue);
    expect(store.orphanedPending(), isEmpty);
    expect(Directory(p.join(store.root.path, 'pending', 'failed')).listSync().length, 1);
  });
}
