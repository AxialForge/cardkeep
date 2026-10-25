import 'dart:io';

import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/followups/followups_repository.dart';
import 'package:card_organizer/core/followups/reminders.dart';
import 'package:card_organizer/core/settings/settings_repository.dart';
import 'package:card_organizer/core/transfer/backup.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository s;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    s = SettingsRepository(db);
  });
  tearDown(() => db.close());

  test('new settings start where the app has always behaved', () async {
    expect(await s.appLock(), isFalse);
    expect(await s.lockAfter(), 1);
    expect(await s.reminderMinutes(), 8 * 60);
    expect(await s.purgeDays(), 7);
    expect(await s.backupSchedule(), BackupSchedule.off);
    expect(await s.exportNotes(), isTrue);
    expect(await s.exportImages(), isFalse);
  });

  test('choices are saved, and a value that is not one of the choices falls back', () async {
    await s.setLockAfter(15);
    await s.setPurgeDays(30);
    await s.setReminderMinutes(9 * 60 + 30);
    expect(await s.lockAfter(), 15);
    expect(await s.purgeDays(), 30);
    expect(await s.reminderMinutes(), 570);
    await s.setLockAfter(7);
    await s.setPurgeDays(3);
    await s.setReminderMinutes(99999);
    expect(await s.lockAfter(), 1);
    expect(await s.purgeDays(), 7);
    expect(await s.reminderMinutes(), 8 * 60);
  });

  test('the backup schedule keeps the old weekly switch in step', () async {
    await s.setAutoBackup(true);
    expect(await s.backupSchedule(), BackupSchedule.weekly);
    await s.setBackupSchedule(BackupSchedule.daily);
    expect(await s.autoBackup(), isTrue);
    expect(await s.backupSchedule(), BackupSchedule.daily);
    await s.setBackupSchedule(BackupSchedule.off);
    expect(await s.autoBackup(), isFalse);
    expect(BackupSchedule.daily.every, const Duration(days: 1));
    expect(BackupSchedule.off.every, isNull);
  });

  test('a library from before the schedule existed: the old weekly switch still means weekly', () async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: 'auto_backup', value: 'true', updatedAt: Value(DateTime.now())),
        );
    expect(await s.backupSchedule(), BackupSchedule.weekly);
  });

  test('export defaults are saved', () async {
    await s.setExportNotes(false);
    await s.setExportImages(true);
    expect(await s.exportNotes(), isFalse);
    expect(await s.exportImages(), isTrue);
  });

  group('reminder time (S15.1)', () {
    FollowupItem item(String id, DateTime due) => FollowupItem(personId: id, name: id, first: id, due: due);
    final now = DateTime(2026, 10, 22, 23, 2);

    test('reminds on the due day at the chosen time', () {
      final f = item('a', DateTime(2026, 10, 23, 8));
      expect(Reminders.plan([f], now, {}, minutes: 9 * 60 + 30).single.$2, DateTime(2026, 10, 23, 9, 30));
      expect(Reminders.plan([f], now, {}).single.$2, DateTime(2026, 10, 23, 8), reason: 'default stays 08:00');
    });

    test('a time later today is still ahead; one already past gets the one-minute catch-up', () {
      final today = item('a', DateTime(2026, 10, 22, 8));
      expect(Reminders.plan([today], now, {}, minutes: 23 * 60 + 30).single.$2, DateTime(2026, 10, 22, 23, 30));
      expect(Reminders.plan([today], now, {}, minutes: 9 * 60).single.$2, now.add(const Duration(minutes: 1)));
    });
  });

  group('backups on the phone', () {
    late Directory docs;
    setUp(() async => docs = await Directory.systemTemp.createTemp('ck_sched'));
    tearDown(() => docs.delete(recursive: true));

    test('Back up now writes a backup and keeps the newest four', () async {
      var t = DateTime(2026, 10, 24, 9, 0);
      final b = Backups(db, docs, clock: () => t);
      for (var i = 0; i < 6; i++) {
        t = t.add(const Duration(minutes: 2));
        final f = await b.backupNow();
        expect(f.existsSync(), isTrue, reason: 'backup $i');
        // Distinct modified times so "newest" is well defined.
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(b.listAuto().length, 4);
    });

    test('Daily makes one after a day; Weekly waits a week', () async {
      final b = Backups(db, docs, clock: () => DateTime.now().add(const Duration(hours: 25)));
      await Backups(db, docs).backupNow();
      expect(await b.autoBackupIfDue(every: BackupSchedule.weekly.every!), isNull);
      expect(await b.autoBackupIfDue(every: BackupSchedule.daily.every!), isNotNull);
    });
  });
}
