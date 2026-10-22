import 'dart:io';

import 'package:card_organizer/core/transfer/backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const sqliteHeader = 'SQLite format 3\u0000';

/// A fake library: a "database" file whose text says which copy it is, and
/// one card image per copy.
void library(Directory at, String label, {bool cards = true}) {
  File(p.join(at.path, dbFileName))
    ..createSync(recursive: true)
    ..writeAsStringSync('$sqliteHeader$label');
  if (cards) {
    File(p.join(at.path, 'cards', 'rectified', '$label.jpg'))
      ..createSync(recursive: true)
      ..writeAsStringSync(label);
  }
}

String? dbLabel(String path) {
  final f = File(path);
  return f.existsSync() ? f.readAsStringSync().replaceFirst(sqliteHeader, '') : null;
}

Future<Directory> setUpRestore({bool olderFallback = true}) async {
  final docs = await Directory.systemTemp.createTemp('ck_restore');
  library(docs, 'ORIGINAL');
  if (olderFallback) library(Directory(p.join(docs.path, 'before_restore')), 'OLDER');
  final staged = Directory(p.join(docs.path, 'restore_pending'));
  library(staged, 'RESTORED');
  File(p.join(staged.path, '.ready')).writeAsStringSync('x');
  return docs;
}

void expectRestored(Directory docs) {
  expect(dbLabel(p.join(docs.path, dbFileName)), 'RESTORED');
  expect(File(p.join(docs.path, 'cards', 'rectified', 'RESTORED.jpg')).existsSync(), isTrue);
  expect(
    dbLabel(p.join(docs.path, 'before_restore', dbFileName)),
    'ORIGINAL',
    reason: 'fallback = the pre-restore data',
  );
  expect(File(p.join(docs.path, 'before_restore', 'cards', 'rectified', 'ORIGINAL.jpg')).existsSync(), isTrue);
  expect(Directory(p.join(docs.path, 'restore_pending')).existsSync(), isFalse);
  expect(Directory(p.join(docs.path, 'before_restore.new')).existsSync(), isFalse);
}

void main() {
  test('normal restore', () async {
    final docs = await setUpRestore();
    addTearDown(() => docs.delete(recursive: true));
    expect(await applyPendingRestore(docs), RestoreOutcome.restored);
    expectRestored(docs);
  });

  // Count the steps once, then kill the process at every one of them.
  test('killed at any step: the next start finishes it and nothing is lost (MOB-REL-0001)', () async {
    final steps = <String>[];
    final probe = await setUpRestore();
    await applyPendingRestore(probe, onStep: steps.add);
    await probe.delete(recursive: true);
    expect(steps.length, greaterThan(6));

    for (var kill = 0; kill < steps.length; kill++) {
      final docs = await setUpRestore();
      var n = 0;
      await expectLater(
        applyPendingRestore(
          docs,
          onStep: (s) {
            if (n++ == kill) throw StateError('killed after ${steps[kill]}');
          },
        ),
        throwsStateError,
      );
      // The next start.
      expect(
        await applyPendingRestore(docs),
        anyOf(RestoreOutcome.restored, RestoreOutcome.none),
        reason: 'kill $kill',
      );
      expectRestored(docs);
      await docs.delete(recursive: true);
    }
  });

  test('killed, then the app opened and made an empty database before the next start', () async {
    for (final killAfter in ['old', 'moved card_organizer.sqlite']) {
      final docs = await setUpRestore();
      await expectLater(
        applyPendingRestore(
          docs,
          onStep: (s) {
            if (s == killAfter) throw StateError('killed');
          },
        ),
        throwsStateError,
      );
      // The app started anyway (restore failed) and drift created an empty DB and cards/.
      if (!File(p.join(docs.path, dbFileName)).existsSync()) library(docs, 'EMPTY', cards: false);
      Directory(p.join(docs.path, 'cards', 'thumb')).createSync(recursive: true);
      expect(await applyPendingRestore(docs), RestoreOutcome.restored, reason: killAfter);
      expect(dbLabel(p.join(docs.path, dbFileName)), 'RESTORED', reason: killAfter);
      expect(dbLabel(p.join(docs.path, 'before_restore', dbFileName)), 'ORIGINAL', reason: killAfter);
      await docs.delete(recursive: true);
    }
  });

  test('a damaged staged database is refused and the current data is untouched', () async {
    final docs = await setUpRestore();
    addTearDown(() => docs.delete(recursive: true));
    File(p.join(docs.path, 'restore_pending', dbFileName)).writeAsStringSync('not a database');
    expect(await applyPendingRestore(docs), RestoreOutcome.refused);
    expect(dbLabel(p.join(docs.path, dbFileName)), 'ORIGINAL');
    expect(dbLabel(p.join(docs.path, 'before_restore', dbFileName)), 'OLDER', reason: 'older fallback kept');
    expect(Directory(p.join(docs.path, 'restore_pending')).existsSync(), isFalse);
  });
}
