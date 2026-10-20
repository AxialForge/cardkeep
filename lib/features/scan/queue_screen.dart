import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/drawer.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/cards/card_queue_repository.dart';
import '../../scan/scan_worker.dart';
import 'scan_review.dart';

/// Review queue (mockup Queue.dc.html): cards read but not yet saved, with
/// counts for what was saved automatically today and what is still reading.
class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  void _open(BuildContext context, QueueItem i) => context.push(
    '/contact/new',
    extra: ScanHandoff(cardId: i.cardId, front: i.front, back: i.back),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(queueProvider).value ?? const <QueueItem>[];
    final stats = ref.watch(queueStatsProvider).value;
    final reading = ref.watch(scanWorkerProvider).reading;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Tokens.groundOverlay,
      child: Scaffold(
        drawer: const AppDrawer(current: '/queue'),
        bottomNavigationBar: items.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Tokens.gutter, 8, Tokens.gutter, 12),
                  child: FilledButton(
                    onPressed: () => _open(context, items.first),
                    child: Text(items.length == 1 ? 'Review the last card' : 'Review next, ${items.length} left'),
                  ),
                ),
              ),
        body: SafeArea(
          bottom: false,
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
                      icon: Icons.photo_camera_outlined,
                      tooltip: 'Scan cards',
                      onPressed: () => context.push('/scan'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                child: Text('Review queue', style: AppText.display),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Tokens.gutter),
                child: Row(
                  children: [
                    _Tile('${stats?.autoSavedToday ?? 0}', 'Saved automatically today', dark: true),
                    const SizedBox(width: 8),
                    _Tile('${items.length}', 'Need a quick look'),
                    const SizedBox(width: 8),
                    _Tile('$reading', 'Still reading'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (items.isEmpty && reading == 0)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: EmptyState(
                    icon: Icons.task_alt,
                    title: 'Nothing to review',
                    message: 'Cards you scan wait here until you check them. Clear ones go straight to Contacts.',
                  ),
                ),
              for (final i in items)
                Dismissible(
                  key: ValueKey(i.cardId),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 28),
                    child: Icon(Icons.delete_outline, color: Tokens.hotFg),
                  ),
                  onDismissed: (_) async {
                    final q = await ref.read(cardQueueProvider.future);
                    await q.discard(i.cardId);
                    if (context.mounted) {
                      showMessage(
                        context,
                        'Card removed',
                        action: SnackBarAction(label: 'Undo', onPressed: () => q.restore(i.cardId)),
                      );
                    }
                  },
                  child: Panel(
                    padding: EdgeInsets.zero,
                    child: InkWell(
                      onTap: () => _open(context, i),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: i.front.thumb.isEmpty
                                  ? Container(width: 88, height: 52, color: Tokens.selected)
                                  : Image.memory(i.front.thumb, width: 88, height: 52, fit: BoxFit.cover),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(i.front.parsed?.name?.value ?? 'No name found', style: AppText.bodyStrong),
                                  if (i.front.parsed?.company?.value case final co?)
                                    Text(co, style: AppText.secondary, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  if (i.reasons.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          for (final r in i.reasons.toSet())
                                            Pill(r, bg: Tokens.amberBg, fg: Tokens.amberFg),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (items.isNotEmpty || reading > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    reading > 0
                        ? 'Reading continues while you keep scanning. Swipe a card left to remove it.'
                        : 'Cards read clearly are already in Contacts. Swipe a card left to remove it.',
                    style: AppText.secondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String value, label;
  final bool dark;
  const _Tile(this.value, this.label, {this.dark = false});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(minHeight: 96),
      decoration: BoxDecoration(
        color: dark ? Tokens.strong : Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.radius),
        border: Border.all(color: dark ? Tokens.strong : Tokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppText.title.copyWith(color: dark ? Tokens.onStrong : Tokens.ink)),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppText.secondary.copyWith(fontSize: 12.5, color: dark ? Tokens.onStrongMuted : Tokens.ink2),
          ),
        ],
      ),
    ),
  );
}
