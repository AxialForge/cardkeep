import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import 'conflict_view.dart';
import 'sync_providers.dart';

/// The open conflicts, named and grouped. Re-reads whenever one is resolved or a
/// sync adds more.
final conflictGroupsProvider = FutureProvider.autoDispose<List<ConflictGroup>>((ref) async {
  ref.watch(openConflictsProvider);
  final engine = await ref.watch(syncEngineProvider.future);
  return describeConflicts(ref.read(databaseProvider), await engine.conflicts());
});

/// Fields changed on both devices (S16.6): pick a side per field, or one side
/// for all. Nothing is lost until you choose: each device keeps its own value
/// meanwhile.
class ConflictsScreen extends ConsumerWidget {
  const ConflictsScreen({super.key});

  Future<void> _resolve(BuildContext context, WidgetRef ref, ConflictItem item, {required bool mine}) async {
    final engine = await ref.read(syncEngineProvider.future);
    if (mine) {
      await engine.resolveMine(item.conflict.id);
    } else {
      await engine.resolveTheirs(item.conflict.id);
    }
    ref.invalidate(conflictGroupsProvider);
  }

  Future<void> _all(BuildContext context, WidgetRef ref, List<ConflictGroup> groups, {required bool mine}) async {
    final n = groups.fold<int>(0, (a, g) => a + g.items.length);
    final ok = await confirm(
      context,
      title: mine ? 'Keep this phone\'s values?' : 'Use your PC\'s values?',
      message: mine
          ? 'For all $n fields, the values on this phone stay and replace the PC\'s at the next sync.'
          : 'For all $n fields, this phone takes the PC\'s values.',
      action: mine ? 'Keep this phone\'s' : 'Use the PC\'s',
    );
    if (!ok) return;
    final engine = await ref.read(syncEngineProvider.future);
    for (final g in groups) {
      for (final i in g.items) {
        if (mine) {
          await engine.resolveMine(i.conflict.id);
        } else {
          await engine.resolveTheirs(i.conflict.id);
        }
      }
    }
    ref.invalidate(conflictGroupsProvider);
    if (context.mounted) showMessage(context, 'Done. The choices reach your PC at the next sync.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(conflictGroupsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Changed on both devices')),
      body: groups.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(padding: const EdgeInsets.all(24), child: Text('$e')),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.check_circle_outline,
              title: 'Nothing to choose',
              message: 'Every change from your PC fits with this phone.',
            );
          }
          final n = list.fold<int>(0, (a, g) => a + g.items.length);
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  '$n field${n == 1 ? '' : 's'} changed on this phone and on your PC at about the same time. Until you '
                  'choose, each device keeps its own value. Nothing is lost.',
                  style: AppText.secondary,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => _all(context, ref, list, mine: true),
                      child: const Text('Keep all this phone\'s'),
                    ),
                    OutlinedButton(
                      onPressed: () => _all(context, ref, list, mine: false),
                      child: const Text('Use all the PC\'s'),
                    ),
                  ],
                ),
              ),
              for (final g in list)
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.title, style: AppText.heading),
                      Text(g.subtitle, style: AppText.secondary),
                      for (final item in g.items) ...[
                        const Divider(height: 24),
                        Text(item.fieldLabel, style: AppText.bodyStrong),
                        const SizedBox(height: 6),
                        _Choice(
                          who: 'On this phone',
                          value: item.mine,
                          action: 'Keep this',
                          onTap: () => _resolve(context, ref, item, mine: true),
                        ),
                        const SizedBox(height: 8),
                        _Choice(
                          who: 'On your PC',
                          value: item.theirs,
                          action: 'Use this',
                          onTap: () => _resolve(context, ref, item, mine: false),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final String who;
  final String value;
  final String action;
  final VoidCallback onTap;
  const _Choice({required this.who, required this.value, required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(who, style: AppText.overline),
      const SizedBox(height: 2),
      Text(value, style: AppText.body),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(onPressed: onTap, child: Text(action)),
      ),
    ],
  );
}
