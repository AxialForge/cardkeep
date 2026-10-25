import 'package:card_organizer/app/providers.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/lock/auth_service.dart';
import 'package:card_organizer/core/lock/lock_controller.dart';
import 'package:card_organizer/core/settings/settings_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuth implements AuthService {
  bool available = true;
  AuthResult next = AuthResult.success;
  int asked = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<AuthResult> authenticate(String reason) async {
    asked++;
    return next;
  }
}

void main() {
  late AppDatabase db;
  late FakeAuth auth;
  late DateTime clock;
  late ProviderContainer c;

  Future<ProviderContainer> make({bool startLocked = false}) async {
    final c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        authServiceProvider.overrideWithValue(auth),
        lockClockProvider.overrideWithValue(() => clock),
        initialLockedProvider.overrideWithValue(startLocked),
      ],
    );
    // Providers pause without a listener (Riverpod 3), as they would not in the app,
    // where the lock controller listens. Listen so the settings streams deliver.
    c.listen(appLockProvider, (_, _) {});
    c.listen(lockAfterProvider, (_, _) {});
    await c.read(appLockProvider.future);
    await c.read(lockAfterProvider.future);
    c.read(lockControllerProvider);
    return c;
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    auth = FakeAuth();
    clock = DateTime(2026, 10, 24, 12);
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  test('lock timing: a short trip does not lock, a long one does (S15.2)', () async {
    c = await make();
    final left = DateTime(2026, 10, 24, 12);
    expect(lockAfterAbsence(leftAt: left, now: left.add(const Duration(seconds: 59)), afterMinutes: 1), isFalse);
    expect(lockAfterAbsence(leftAt: left, now: left.add(const Duration(minutes: 1)), afterMinutes: 1), isTrue);
    expect(lockAfterAbsence(leftAt: left, now: left.add(const Duration(minutes: 4)), afterMinutes: 5), isFalse);
    expect(lockAfterAbsence(leftAt: left, now: left.add(const Duration(minutes: 15)), afterMinutes: 15), isTrue);
    expect(
      lockAfterAbsence(leftAt: left, now: left, afterMinutes: 0),
      isTrue,
      reason: 'right away',
    );
  });

  test('App lock off: leaving the app never locks it', () async {
    c = await make();
    final lock = c.read(lockControllerProvider.notifier);
    lock.leftApp();
    clock = clock.add(const Duration(hours: 3));
    lock.returned();
    expect(c.read(lockControllerProvider).locked, isFalse);
  });

  test('App lock on, after 5 minutes: locks only after the time with a fake clock', () async {
    await settingsOf(db).setAppLock(true);
    await settingsOf(db).setLockAfter(5);
    c = await make();
    final lock = c.read(lockControllerProvider.notifier);
    lock.leftApp();
    clock = clock.add(const Duration(minutes: 4));
    lock.returned();
    expect(c.read(lockControllerProvider).locked, isFalse);
    lock.leftApp();
    clock = clock.add(const Duration(minutes: 5));
    lock.returned();
    expect(c.read(lockControllerProvider).locked, isTrue);
  });

  test('Right away locks as soon as CardKeep goes to the background', () async {
    await settingsOf(db).setAppLock(true);
    await settingsOf(db).setLockAfter(0);
    c = await make();
    c.read(lockControllerProvider.notifier).leftApp();
    expect(c.read(lockControllerProvider).locked, isTrue);
  });

  test('opens locked when App lock was on at start, and unlocks with the phone check', () async {
    await settingsOf(db).setAppLock(true);
    c = await make(startLocked: true);
    expect(c.read(lockControllerProvider).locked, isTrue);
    await c.read(lockControllerProvider.notifier).unlock();
    expect(auth.asked, 1);
    expect(c.read(lockControllerProvider).locked, isFalse);
  });

  test('a failed or cancelled check keeps it locked and says to try again', () async {
    await settingsOf(db).setAppLock(true);
    c = await make(startLocked: true);
    auth.next = AuthResult.cancelled;
    await c.read(lockControllerProvider.notifier).unlock();
    var s = c.read(lockControllerProvider);
    expect(s.locked, isTrue);
    expect(s.note, LockNote.tryAgain);
    expect(s.unlocking, isFalse);
    auth.next = AuthResult.lockedOut;
    await c.read(lockControllerProvider.notifier).unlock();
    s = c.read(lockControllerProvider);
    expect(s.note, LockNote.waitAndRetry);
    auth.next = AuthResult.success;
    await c.read(lockControllerProvider.notifier).unlock();
    expect(c.read(lockControllerProvider).locked, isFalse);
  });

  test('a phone with no screen lock: App lock switches itself off instead of locking the owner out', () async {
    await settingsOf(db).setAppLock(true);
    c = await make(startLocked: true);
    auth.available = false;
    await c.read(lockControllerProvider.notifier).unlock();
    final s = c.read(lockControllerProvider);
    expect(s.locked, isFalse);
    expect(s.note, LockNote.noScreenLock);
    expect(await settingsOf(db).appLock(), isFalse);
  });

  test('going to the background while the phone prompt is open does not count as leaving', () async {
    await settingsOf(db).setAppLock(true);
    await settingsOf(db).setLockAfter(0);
    c = await make(startLocked: true);
    final lock = c.read(lockControllerProvider.notifier);
    // A prompt that never answers while we poke the lifecycle.
    final pending = lock.unlock();
    lock.leftApp();
    lock.returned();
    await pending;
    expect(c.read(lockControllerProvider).locked, isFalse);
  });

  test('turning App lock off unlocks a locked screen', () async {
    await settingsOf(db).setAppLock(true);
    c = await make(startLocked: true);
    await settingsOf(db).setAppLock(false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.read(lockControllerProvider).locked, isFalse);
  });
}

SettingsRepository settingsOf(AppDatabase db) => SettingsRepository(db);
