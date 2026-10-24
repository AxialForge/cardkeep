import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import 'content/content_model.dart';
import 'onboarding_gate.dart';

/// What an upgrading user hears about (S15a.8). Plain data so the Help hub and
/// the release notes can reuse it.
const whatsNewItems = <LessonStep>[
  LessonStep(
    'Sweep scan',
    'Lay cards out and move the phone over them. Each one is outlined, read once and marked Done.',
  ),
  LessonStep(
    'Places',
    'Shops, restaurants and suppliers with no person on the card are kept as Places, with your own categories.',
  ),
  LessonStep(
    'Tidy-up',
    'Merge all obvious duplicates in one step with an Undo, and company pages that gather everyone at a company.',
  ),
  LessonStep('Help & tips', 'A guided tour, short lessons, a searchable help page and first-visit tips. All optional.'),
];

enum WhatsNewChoice { tour, tips, notNow }

/// The short "What's new" sheet for someone who already uses CardKeep. Returns
/// what they chose after saving it; the caller opens the tour for [WhatsNewChoice.tour].
Future<WhatsNewChoice?> showWhatsNewSheet(BuildContext context, WidgetRef ref) async {
  final choice = await showModalBottomSheet<WhatsNewChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Tokens.surface,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(header: true, child: Text("What's new in CardKeep", style: AppText.title)),
            const SizedBox(height: 12),
            for (final i in whatsNewItems)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Semantics(
                  container: true,
                  label: '${i.title}. ${i.body}',
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i.title, style: AppText.bodyStrong),
                        Text(i.body, style: AppText.body),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            FilledButton(onPressed: () => Navigator.pop(c, WhatsNewChoice.tour), child: const Text('Take the tour')),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.pop(c, WhatsNewChoice.tips),
              child: const Text('Show me tips as I go'),
            ),
            TextButton(onPressed: () => Navigator.pop(c, WhatsNewChoice.notNow), child: const Text('Not now')),
            Text('You can find all of this later in Settings, under Help.', style: AppText.secondary),
          ],
        ),
      ),
    ),
  );
  // Swiping the sheet away counts as "Not now".
  final result = choice ?? WhatsNewChoice.notNow;
  final s = ref.read(settingsRepoProvider);
  await s.setOnboardingVersion(tourVersion);
  await s.setWhatsNewSeen(tourVersion);
  await s.setTipsEnabled(result != WhatsNewChoice.notNow);
  return result;
}
