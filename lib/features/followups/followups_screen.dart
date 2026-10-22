import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/drawer.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/followups/followups_repository.dart';

final followupsRepoProvider = Provider((ref) => FollowupsRepository(ref.watch(databaseProvider)));
final openFollowupsProvider = StreamProvider<List<FollowupItem>>((ref) => ref.watch(followupsRepoProvider).watchOpen());

/// Follow-ups (mockup Followups, S11.2): Overdue, This week, Later.
class FollowupsScreen extends ConsumerWidget {
  const FollowupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(openFollowupsProvider).value ?? const <FollowupItem>[];
    final now = DateTime.now();
    final groups = {for (final g in FollowupGroup.values) g: items.where((f) => groupOf(f.due, now) == g).toList()};
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Tokens.groundOverlay,
      child: Scaffold(
        drawer: const AppDrawer(current: '/followups'),
        body: SafeArea(
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
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                child: Text('Follow-ups', style: AppText.display),
              ),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: EmptyState(
                    icon: Icons.task_alt,
                    title: 'All caught up',
                    message: 'Set a follow-up date on a contact, or from an event, and it shows here with a reminder.',
                  ),
                ),
              for (final g in FollowupGroup.values)
                if (groups[g]!.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Overline('${g.label} (${groups[g]!.length})'),
                  ),
                  Panel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [for (final f in groups[g]!) _FollowupTile(f, overdue: g == FollowupGroup.overdue)],
                    ),
                  ),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FollowupTile extends ConsumerWidget {
  final FollowupItem f;
  final bool overdue;
  const _FollowupTile(this.f, {required this.overdue});

  Future<void> _email(BuildContext context, WidgetRef ref) async {
    final mail = followupEmail(f);
    final opened = await ref.read(launcherProvider).email(f.email!, subject: mail.subject, body: mail.body);
    if (!opened || !context.mounted) return;
    // S11.8: only marked as done when you say it was sent.
    final sent = await confirm(
      context,
      title: 'Did you send it?',
      message: 'Mark the follow-up with ${f.name} as done.',
      action: 'Mark done',
    );
    if (sent) await ref.read(followupsRepoProvider).markDone(f.personId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(followupsRepoProvider);
    final sub = [if (f.company != null) f.company!, if (f.eventName != null) 'met at ${f.eventName}'].join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      title: Text(f.name.isEmpty ? '(No name)' : f.name, style: AppText.bodyStrong),
      subtitle: Text(
        [DateFormat('EEE, MMM d').format(f.due), if (sub.isNotEmpty) sub].join(' · '),
        style: AppText.secondary.copyWith(color: overdue ? Tokens.hotFg : null),
      ),
      onTap: () => context.push('/contact/${f.personId}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (f.email != null)
            IconButton(
              tooltip: 'Draft follow-up email',
              icon: const Icon(Icons.mail_outline),
              onPressed: () => _email(context, ref),
            ),
          PopupMenuButton<int>(
            tooltip: 'Later',
            icon: const Icon(Icons.snooze),
            onSelected: (days) => repo.reschedule(f.personId, DateTime.now().add(Duration(days: days))),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 1, child: Text('Tomorrow')),
              PopupMenuItem(value: 3, child: Text('In 3 days')),
              PopupMenuItem(value: 7, child: Text('Next week')),
            ],
          ),
          IconButton(
            tooltip: 'Done',
            icon: Icon(Icons.check_circle_outline, color: Tokens.brassText),
            onPressed: () async {
              await repo.markDone(f.personId);
              if (context.mounted) showMessage(context, 'Done: ${f.name}');
            },
          ),
        ],
      ),
    );
  }
}
