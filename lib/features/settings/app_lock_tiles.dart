import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/lock/auth_service.dart';
import '../../core/lock/lock_controller.dart';
import '../../core/settings/settings_repository.dart';

/// Words for a "lock after" choice.
String lockAfterLabel(int minutes) => switch (minutes) {
  0 => 'Right away',
  1 => 'After 1 minute',
  _ => 'After $minutes minutes',
};

/// Turns App lock on after the phone has checked the person once, so a lock that
/// cannot be opened is never switched on. Returns a short message when it could
/// not be turned on, or null when it is on.
Future<String?> turnOnAppLock(WidgetRef ref) async {
  final auth = ref.read(authServiceProvider);
  if (!await auth.isAvailable()) {
    return 'This phone has no screen lock yet. Set a PIN, pattern, password or fingerprint in your phone\'s settings, then try again.';
  }
  final r = await auth.authenticate('Turn on App lock');
  switch (r) {
    case AuthResult.success:
      await ref.read(settingsRepoProvider).setAppLock(true);
      return null;
    case AuthResult.lockedOut:
      return 'Too many tries. Wait a moment and try again.';
    case AuthResult.unavailable:
      return 'This phone has no screen lock yet. Set a PIN, pattern, password or fingerprint in your phone\'s settings, then try again.';
    case AuthResult.failed || AuthResult.cancelled:
      return 'App lock stays off. It only turns on after your phone has checked it is you.';
  }
}

/// The App lock switch and its "Lock after" choice (Settings > Privacy and the
/// set-up page of the tour).
class AppLockTiles extends ConsumerWidget {
  const AppLockTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(appLockProvider).value ?? false;
    final after = ref.watch(lockAfterProvider).value ?? 1;
    final settings = ref.read(settingsRepoProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          value: on,
          activeThumbColor: Tokens.brass,
          onChanged: (v) async {
            if (!v) {
              await settings.setAppLock(false);
              return;
            }
            final problem = await turnOnAppLock(ref);
            if (problem != null && context.mounted) showMessage(context, problem);
          },
          title: Text('App lock', style: AppText.body),
          subtitle: Text(
            'Ask for your fingerprint, face or phone passcode to open CardKeep. Your phone does the check; CardKeep has no password of its own to forget. Also hides CardKeep in the app switcher and blocks screenshots.',
            style: AppText.secondary,
          ),
        ),
        if (on) ...[
          const Divider(indent: 16, endIndent: 16),
          DropdownRow<int>(
            title: 'Lock',
            subtitle: 'How long CardKeep can be in the background before it asks again',
            value: after,
            items: [for (final m in lockAfterChoices) DropdownMenuItem(value: m, child: Text(lockAfterLabel(m)))],
            onChanged: (v) => v == null ? null : settings.setLockAfter(v),
          ),
        ],
      ],
    );
  }
}
