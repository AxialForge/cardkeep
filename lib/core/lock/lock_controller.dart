import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'auth_service.dart';

/// True when CardKeep should open locked: App lock was on when the app started.
/// Set in main(); tests leave it off.
final initialLockedProvider = Provider<bool>((ref) => false);

/// The phone's fingerprint, face or passcode check. Replaced by a fake in tests.
final authServiceProvider = Provider<AuthService>((ref) => LocalAuthService());

/// The time source for lock timing. Replaced by a fake clock in tests.
final lockClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// App lock is on (Settings > Privacy).
final appLockProvider = StreamProvider<bool>((ref) => ref.watch(settingsRepoProvider).watchAppLock());

/// Minutes away before CardKeep locks again; 0 locks as soon as it goes to the background.
final lockAfterProvider = StreamProvider<int>((ref) => ref.watch(settingsRepoProvider).watchLockAfter());

/// Whether leaving the app for [afterMinutes] minutes means it must lock (S15.2).
/// Zero means every time. Pure so the timing is easy to test.
bool lockAfterAbsence({required DateTime leftAt, required DateTime now, required int afterMinutes}) =>
    afterMinutes <= 0 || now.difference(leftAt) >= Duration(minutes: afterMinutes);

class LockState {
  /// CardKeep is covered by the lock screen.
  final bool locked;

  /// The phone's prompt is open, so going to the background is not "leaving".
  final bool unlocking;

  /// Why the last try did not open it, or why App lock switched itself off.
  final LockNote? note;
  const LockState({this.locked = false, this.unlocking = false, this.note});

  LockState copyWith({bool? locked, bool? unlocking, LockNote? note, bool clearNote = false}) => LockState(
    locked: locked ?? this.locked,
    unlocking: unlocking ?? this.unlocking,
    note: clearNote ? null : (note ?? this.note),
  );
}

enum LockNote {
  /// Did not match, or the prompt was closed.
  tryAgain('That did not work. Tap Unlock to try again.'),

  /// Too many wrong tries.
  waitAndRetry('Too many tries. Wait a moment, then tap Unlock.'),

  /// The phone no longer has a screen lock, so App lock switched itself off.
  noScreenLock('App lock was turned off because this phone has no screen lock.');

  final String text;
  const LockNote(this.text);
}

/// Locks CardKeep when it has been away long enough and opens it again with the
/// phone's own check. Reminder taps still open the contact underneath; the lock
/// screen simply sits on top.
class LockController extends Notifier<LockState> {
  DateTime? _leftAt;
  bool _enabled = false;
  int _after = 1;

  @override
  LockState build() {
    // Settings may not have loaded yet; main() already told us whether to open locked.
    final startLocked = ref.read(initialLockedProvider);
    _enabled = startLocked || (ref.read(appLockProvider).value ?? false);
    _after = ref.read(lockAfterProvider).value ?? 1;
    ref.listen<AsyncValue<bool>>(appLockProvider, (_, next) {
      final on = next.value;
      if (on == null) return;
      _enabled = on;
      if (!on) {
        _leftAt = null;
        if (state.locked) state = state.copyWith(locked: false, clearNote: true);
      }
    });
    ref.listen<AsyncValue<int>>(lockAfterProvider, (_, next) {
      if (next.value case final m?) _after = m;
    });
    return LockState(locked: startLocked);
  }

  DateTime _now() => ref.read(lockClockProvider)();

  /// CardKeep went to the background.
  void leftApp() {
    if (!_enabled || state.unlocking) return;
    _leftAt ??= _now();
    if (_after <= 0 && !state.locked) state = state.copyWith(locked: true, clearNote: true);
  }

  /// CardKeep came back to the front.
  void returned() {
    final left = _leftAt;
    _leftAt = null;
    if (!_enabled || left == null || state.unlocking || state.locked) return;
    if (lockAfterAbsence(leftAt: left, now: _now(), afterMinutes: _after)) {
      state = state.copyWith(locked: true, clearNote: true);
    }
  }

  /// Asks the phone to check the person. Does nothing while a check is open.
  Future<void> unlock() async {
    if (state.unlocking || !state.locked) return;
    state = state.copyWith(unlocking: true, clearNote: true);
    final auth = ref.read(authServiceProvider);
    try {
      if (!await auth.isAvailable()) {
        await _noScreenLock();
        return;
      }
      final r = await auth.authenticate('Unlock CardKeep');
      switch (r) {
        case AuthResult.success:
          _leftAt = null;
          state = const LockState();
        case AuthResult.unavailable:
          await _noScreenLock();
        case AuthResult.lockedOut:
          state = state.copyWith(unlocking: false, note: LockNote.waitAndRetry);
        case AuthResult.failed || AuthResult.cancelled:
          state = state.copyWith(unlocking: false, note: LockNote.tryAgain);
      }
    } catch (_) {
      state = state.copyWith(unlocking: false, note: LockNote.tryAgain);
    }
  }

  /// With no screen lock set, anyone holding the phone can open everything
  /// anyway; App lock switches itself off rather than locking the owner out.
  Future<void> _noScreenLock() async {
    await ref.read(settingsRepoProvider).setAppLock(false);
    _enabled = false;
    state = const LockState(note: LockNote.noScreenLock);
  }

  /// The note was shown; stop showing it.
  void clearNote() {
    if (state.note != null) state = state.copyWith(clearNote: true);
  }
}

final lockControllerProvider = NotifierProvider<LockController, LockState>(LockController.new);
