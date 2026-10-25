import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/lock/lock_controller.dart';

/// Covers CardKeep while App lock is closed (S15.2). Nothing from the library is
/// drawn here: no names, no counts, no card photos.
class LockScreen extends ConsumerWidget {
  const LockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(lockControllerProvider);
    return Material(
      color: Tokens.ground,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Semantics(
              container: true,
              label: 'CardKeep is locked',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Tokens.brandIvory, borderRadius: BorderRadius.circular(18)),
                    child: Image.asset('assets/brand/cardkeep-mark-256.png', semanticLabel: 'CardKeep logo'),
                  ),
                  const SizedBox(height: 24),
                  Text('CardKeep is locked', style: AppText.title, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    'Use your fingerprint, face or phone passcode to open it.',
                    style: AppText.secondary,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: s.unlocking ? null : () => ref.read(lockControllerProvider.notifier).unlock(),
                    icon: const Icon(Icons.lock_open),
                    label: Text(s.unlocking ? 'Checking…' : 'Unlock'),
                  ),
                  if (s.note != null) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(s.note!.text, style: AppText.secondary, textAlign: TextAlign.center),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
