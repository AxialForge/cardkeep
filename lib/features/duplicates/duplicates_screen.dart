import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/drawer.dart';
import '../../app/plural.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/contacts/contacts_repository.dart';
import '../../core/dupes/duplicates_repository.dart';
import '../../core/dupes/matcher.dart';

final duplicatesRepoProvider = Provider(
  (ref) => DuplicatesRepository(ref.watch(databaseProvider), ref.watch(contactsRepoProvider)),
);

/// The whole library scanned for duplicates (S8.3). Re-run with refresh.
final duplicatePairsProvider = FutureProvider.autoDispose<List<DupPair>>(
  (ref) => ref.watch(duplicatesRepoProvider).scanAll(),
);

/// Possible duplicates of one person, for the banner on their detail screen.
final matchesForProvider = FutureProvider.autoDispose.family<List<DupPair>, String>((ref, id) {
  ref.watch(contactDetailProvider(id)); // re-check after edits
  return ref.watch(duplicatesRepoProvider).matchesFor(id);
});

/// Duplicates (mockup Duplicates): pairs with the match reason, merge or dismiss.
class DuplicatesScreen extends ConsumerWidget {
  const DuplicatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairs = ref.watch(duplicatePairsProvider);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Tokens.groundOverlay,
      child: Scaffold(
        drawer: const AppDrawer(current: '/duplicates'),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(duplicatePairsProvider.future),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Tokens.gutter, 8, Tokens.gutter, 0),
                  child: Row(
                    children: [
                      Builder(
                        builder: (c) => DiscButton(
                          icon: Icons.short_text,
                          tooltip: 'Menu',
                          onPressed: () => Scaffold.of(c).openDrawer(),
                        ),
                      ),
                      const Spacer(),
                      DiscButton(
                        icon: Icons.refresh,
                        tooltip: 'Check the whole library again',
                        onPressed: () => ref.invalidate(duplicatePairsProvider),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                  child: Text('Duplicates', style: AppText.display),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    'People who look like the same person: the same mobile, or the same name with the same email '
                    'or company.',
                    style: AppText.secondary,
                  ),
                ),
                ...switch (pairs) {
                  AsyncData(:final value) when value.isEmpty => [
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: EmptyState(
                        icon: Icons.task_alt,
                        title: 'No duplicates',
                        message: 'Every contact looks like a different person.',
                      ),
                    ),
                  ],
                  AsyncData(:final value) => [
                    if (obviousGroups(value).isNotEmpty) _BulkMergePanel(pairs: value),
                    for (final p in value) DuplicatePairTile(pair: p),
                  ],
                  AsyncError(:final error) => [Center(child: Text('Could not check: $error'))],
                  _ => [
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ],
                },
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Merge all obvious duplicates" (S14d.1): a preview of every group, then one
/// merge with one Undo.
class _BulkMergePanel extends ConsumerWidget {
  final List<DupPair> pairs;
  const _BulkMergePanel({required this.pairs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = obviousGroups(pairs);
    final extra = groups.fold<int>(0, (n, g) => n + g.length - 1);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${plural(extra, 'obvious duplicate')} in ${plural(groups.length, 'group')}', style: AppText.bodyStrong),
          const SizedBox(height: 4),
          Text(
            'Same name and the same email or phone, at the same company. You see the list before anything changes.',
            style: AppText.secondary,
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            icon: const Icon(Icons.merge_type),
            label: const Text('Merge all obvious duplicates'),
            onPressed: () => _preview(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _preview(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(duplicatesRepoProvider);
    final plan = await repo.bulkPlan(pairs);
    if (!context.mounted || plan.isEmpty) return;
    final merges = plan.fold<int>(0, (n, g) => n + g.others.length);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text('Merge ${plural(merges, 'contact')}?', style: AppText.heading),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Each group keeps the contact with the newest card. Phones, emails, tags, cards and notes from the '
                  'others are added to it. You can undo straight after.',
                  style: AppText.secondary,
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final g in plan)
                      ListTile(
                        leading: Avatar(_initials(g.keeper.name), size: 36),
                        title: Text(g.keeper.name.isEmpty ? 'No name' : g.keeper.name, style: AppText.bodyStrong),
                        subtitle: Text(
                          [
                            if (g.keeper.company.isNotEmpty) g.keeper.company,
                            '${g.others.length} more cop${g.others.length == 1 ? 'y' : 'ies'} merged in',
                          ].join(' · '),
                          style: AppText.secondary,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: 8,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                    FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text('Merge ${plural(merges, 'contact')}'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final undo = await repo.mergeAll(plan);
    ref.invalidate(duplicatePairsProvider);
    ref.invalidate(matchesForProvider);
    if (!context.mounted) return;
    // The Undo can be tapped after this screen has gone, so it uses the container.
    final container = ProviderScope.containerOf(context);
    showMessage(
      context,
      'Merged ${plural(undo.count, 'duplicate')}',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          await repo.undoAll(undo);
          container.invalidate(duplicatePairsProvider);
          container.invalidate(matchesForProvider);
        },
      ),
    );
  }
}

String _initials(String name) {
  final w = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (w.isEmpty) return '?';
  return (w.length == 1 ? w.first[0] : '${w.first[0]}${w.last[0]}').toUpperCase();
}

/// One possible duplicate pair: both names, why they match, Merge / Not the same.
class DuplicatePairTile extends ConsumerWidget {
  final DupPair pair;
  final VoidCallback? onDone;
  const DuplicatePairTile({super.key, required this.pair, this.onDone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = pair.match;
    Widget side(MatchCandidate c) => Expanded(
      child: Row(
        children: [
          Avatar(_initials(c.name), size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name.isEmpty ? 'No name' : c.name,
                  style: AppText.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  c.company.isNotEmpty
                      ? c.company
                      : (c.mobiles.map(formatPhone).firstOrNull ?? c.emails.firstOrNull ?? ''),
                  style: AppText.secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              side(pair.a),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.drag_handle, color: Tokens.ink2, size: 18),
              ),
              side(pair.b),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              Pill(m.reason.label, bg: Tokens.selected, fg: Tokens.ink),
              if (!m.sameCompany) Pill('Different company: job change?', bg: Tokens.amberBg, fg: Tokens.amberFg),
            ],
          ),
          const SizedBox(height: 8),
          // Side by side when they fit, stacked when not (narrow screens, big text: phone test F15).
          OverflowBar(
            alignment: MainAxisAlignment.spaceBetween,
            overflowAlignment: OverflowBarAlignment.end,
            overflowSpacing: 4,
            children: [
              TextButton(
                onPressed: () async {
                  await ref.read(duplicatesRepoProvider).dismiss(pair.a.id, pair.b.id);
                  ref.invalidate(duplicatePairsProvider);
                  ref.invalidate(matchesForProvider);
                  onDone?.call();
                  if (context.mounted) {
                    showMessage(context, "Marked as different people. They won't be suggested again.");
                  }
                },
                child: const Text('Not the same person'),
              ),
              FilledButton(
                onPressed: () => context.push('/merge/${pair.a.id}/${pair.b.id}'),
                child: const Text('Compare and merge'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
