import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/drawer.dart';
import '../../app/plural.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/db/database.dart';
import '../../core/events/events_repository.dart';
import '../followups/followups_screen.dart';

final eventsRepoProvider = Provider((ref) => EventsRepository(ref.watch(databaseProvider)));
final eventsProvider = StreamProvider<List<Event>>((ref) => ref.watch(eventsRepoProvider).watchEvents());
final eventProvider = StreamProvider.family<Event?, String>((ref, id) => ref.watch(eventsRepoProvider).watchEvent(id));
final eventStatsProvider = StreamProvider.family<EventStats, String>(
  (ref, id) => ref.watch(eventsRepoProvider).watchStats(id),
);
final eventPeopleProvider = StreamProvider.family<List<MetPerson>, String>(
  (ref, id) => ref.watch(eventsRepoProvider).watchPeople(id),
);
final activeSessionProvider = StreamProvider<ActiveSession?>((ref) => ref.watch(eventsRepoProvider).watchActive());

String eventDates(Event e) {
  final s = e.startDate, end = e.endDate;
  if (DateUtils.isSameDay(s, end)) return DateFormat('EEE, MMM d, y').format(s);
  if (s.year == end.year && s.month == end.month) return '${DateFormat('MMM d').format(s)}–${end.day}, ${end.year}';
  return '${DateFormat('MMM d').format(s)} – ${DateFormat('MMM d, y').format(end)}';
}

String typeLabel(EventType t) => switch (t) {
  EventType.tradeShow => 'Trade show',
  EventType.networking => 'Networking',
};

/// Events (mockup Events): current, upcoming and past (S10.1).
class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(eventsProvider).value ?? const <Event>[];
    final now = DateTime.now();
    List<Event> of(EventPhase p) => all.where((e) => phaseOf(e, now) == p).toList();
    final upcoming = of(EventPhase.upcoming)..sort((a, b) => a.startDate.compareTo(b.startDate));
    Widget section(String title, List<Event> list) => list.isEmpty
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 0), child: Overline(title)),
              for (final e in list) _EventTile(e),
            ],
          );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Tokens.groundOverlay,
      child: Scaffold(
        drawer: const AppDrawer(current: '/events'),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/event/new'),
          icon: const Icon(Icons.add),
          label: const Text('New event'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 96),
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
                child: Text('Events', style: AppText.display),
              ),
              if (all.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: EmptyState(
                    icon: Icons.calendar_today_outlined,
                    title: 'No events yet',
                    message: 'Add a trade show or networking event. Cards you scan there are grouped with it.',
                  ),
                ),
              section('Happening now', of(EventPhase.current)),
              section('Upcoming', upcoming),
              section('Past', of(EventPhase.past)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventTile extends ConsumerWidget {
  final Event e;
  const _EventTile(this.e);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(eventStatsProvider(e.uuid)).value;
    final active = ref.watch(activeSessionProvider).value?.event.uuid == e.uuid;
    return Panel(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () => context.push('/event/${e.uuid}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.name, style: AppText.bodyStrong),
                    Text([eventDates(e), if (e.location.isNotEmpty) e.location].join(' · '), style: AppText.secondary),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Pill(typeLabel(e.type), bg: Tokens.selected, fg: Tokens.ink),
                        if (active) Pill('Scanning', bg: Tokens.amberBg, fg: Tokens.amberFg),
                        if (stats != null && stats.contacts > 0)
                          Pill('${stats.contacts} met', bg: Tokens.coldBg, fg: Tokens.coldFg),
                      ],
                    ),
                  ],
                ),
              ),
              if (e.goal != null && stats != null) _GoalRing(done: stats.contacts, goal: e.goal!, size: 48),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalRing extends StatelessWidget {
  final int done, goal;
  final double size;
  const _GoalRing({required this.done, required this.goal, this.size = 96});

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$done of ${plural(goal, 'contact')}',
    child: SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: goal == 0 ? 0 : math.min(1, done / goal),
              strokeWidth: size / 10,
              backgroundColor: Tokens.selected,
              color: Tokens.brandOrange,
            ),
          ),
          Text(
            size > 60 ? '$done/$goal' : '$done',
            style: (size > 60 ? AppText.heading : AppText.label).copyWith(color: Tokens.ink),
          ),
        ],
      ),
    ),
  );
}

/// Event page (mockup EventDetail): goal ring, counts, scan session, people
/// met (S10.5-S10.7).
class EventDetailScreen extends ConsumerWidget {
  final String id;
  const EventDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(eventProvider(id)).value;
    final stats = ref.watch(eventStatsProvider(id)).value;
    final people = ref.watch(eventPeopleProvider(id)).value ?? const <MetPerson>[];
    final active = ref.watch(activeSessionProvider).value;
    final scanning = active?.event.uuid == id;
    final repo = ref.read(eventsRepoProvider);
    if (e == null) return Scaffold(appBar: AppBar());
    final phase = phaseOf(e, DateTime.now());

    Widget tile(String value, String label) => Expanded(
      child: Column(
        children: [
          Text(value, style: AppText.title),
          Text(label, style: AppText.secondary, textAlign: TextAlign.center),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(e.name),
        actions: [
          IconButton(
            tooltip: 'Edit event',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push('/event/$id/edit'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Panel(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Overline(typeLabel(e.type)),
                      const SizedBox(height: 4),
                      Text(eventDates(e), style: AppText.bodyStrong),
                      if (e.location.isNotEmpty) Text(e.location, style: AppText.secondary),
                      if (e.booth != null) Text('Booth ${e.booth}', style: AppText.secondary),
                    ],
                  ),
                ),
                if (e.goal != null) _GoalRing(done: stats?.contacts ?? 0, goal: e.goal!),
              ],
            ),
          ),
          Panel(
            child: Row(
              children: [
                tile('${stats?.cards ?? 0}', 'Cards'),
                tile('${stats?.contacts ?? 0}', 'Contacts'),
                tile('${stats?.companies ?? 0}', 'Companies'),
                tile(
                  '${stats?.followupsDone ?? 0}/${(stats?.followupsDone ?? 0) + (stats?.followupsDue ?? 0)}',
                  'Follow-ups done',
                ),
              ],
            ),
          ),
          if (phase != EventPhase.past || scanning)
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    scanning
                        ? 'Scan session on: every card you scan is added to this event.'
                        : 'Start a scan session and every card you scan goes with this event.',
                    style: AppText.body,
                  ),
                  const SizedBox(height: 10),
                  if (scanning)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(onPressed: repo.endSession, child: const Text('End session')),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => context.push('/scan'),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Scan'),
                          ),
                        ),
                      ],
                    )
                  else
                    FilledButton.icon(
                      onPressed: () async {
                        await repo.startSession(id);
                        if (context.mounted) unawaited(context.push('/scan'));
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start scanning for this event'),
                    ),
                ],
              ),
            ),
          if (people.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton.icon(
                icon: const Icon(Icons.schedule),
                label: Text(
                  'Follow up with everyone on ${DateFormat('MMM d').format(e.endDate.add(Duration(days: e.reminderOffsetDays)))}',
                ),
                onPressed: () async {
                  final n = await ref.read(followupsRepoProvider).applyEventReminders(id);
                  if (context.mounted) {
                    showMessage(
                      context,
                      n == 0
                          ? 'Everyone already has a follow-up'
                          : 'Follow-ups set for $n ${n == 1 ? 'person' : 'people'}',
                    );
                  }
                },
              ),
            ),
          Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 0), child: Overline('Met here (${people.length})')),
          if (people.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Text('No one yet.', style: AppText.secondary),
            )
          else
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final p in people)
                    ListTile(
                      title: Text(p.name, style: AppText.bodyStrong),
                      subtitle: p.company == null ? null : Text(p.company!, style: AppText.secondary),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/contact/${p.id}'),
                    ),
                ],
              ),
            ),
          if (e.notes.isNotEmpty)
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Overline('Notes'),
                  const SizedBox(height: 6),
                  Text(e.notes, style: AppText.body),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// New or edit event (mockup NewEvent, S10.2).
class EventEditScreen extends ConsumerStatefulWidget {
  final String? id;
  const EventEditScreen({super.key, this.id});

  @override
  ConsumerState<EventEditScreen> createState() => _EventEditScreenState();
}

class _EventEditScreenState extends ConsumerState<EventEditScreen> {
  EventDraft? _d;
  final _name = TextEditingController(), _loc = TextEditingController(), _booth = TextEditingController();
  final _goal = TextEditingController(), _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.id == null) {
      final t = DateUtils.dateOnly(DateTime.now());
      _set(EventDraft(start: t, end: t));
    } else {
      ref.read(eventsRepoProvider).watchEvent(widget.id!).first.then((e) {
        if (e != null && mounted) setState(() => _set(EventDraft.of(e)));
      });
    }
  }

  void _set(EventDraft d) {
    _d = d;
    _name.text = d.name;
    _loc.text = d.location;
    _booth.text = d.booth;
    _goal.text = d.goal?.toString() ?? '';
    _notes.text = d.notes;
  }

  @override
  void dispose() {
    for (final c in [_name, _loc, _booth, _goal, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDates() async {
    final d = _d!;
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: d.start, end: d.end.isBefore(d.start) ? d.start : d.end),
    );
    if (r == null) return;
    setState(() {
      d.start = r.start;
      d.end = r.end;
    });
  }

  Future<void> _save() async {
    final d = _d!;
    if (_name.text.trim().isEmpty) return showMessage(context, 'Give the event a name.');
    d
      ..name = _name.text
      ..location = _loc.text
      ..booth = _booth.text
      ..goal = int.tryParse(_goal.text.trim())
      ..notes = _notes.text;
    final id = await ref.read(eventsRepoProvider).save(d, id: widget.id);
    if (!mounted) return;
    widget.id == null ? context.pushReplacement('/event/$id') : context.pop();
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Delete this event?',
      message: 'People you met there stay in Contacts.',
      action: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(eventsRepoProvider).delete(widget.id!);
    if (mounted) context.go('/events');
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.id == null ? 'New event' : 'Edit event'),
        actions: [TextButton(onPressed: d == null ? null : _save, child: const Text('Save'))],
      ),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                TextField(
                  controller: _name,
                  autofocus: widget.id == null,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name', hintText: 'FabTech 2026'),
                ),
                const SizedBox(height: 14),
                SegmentedButton<EventType>(
                  segments: [for (final t in EventType.values) ButtonSegment(value: t, label: Text(typeLabel(t)))],
                  selected: {d.type},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => d.type = s.single),
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.date_range),
                  title: const Text('Dates'),
                  subtitle: Text(
                    DateUtils.isSameDay(d.start, d.end)
                        ? DateFormat('EEE, MMM d, y').format(d.start)
                        : '${DateFormat('MMM d').format(d.start)} – ${DateFormat('MMM d, y').format(d.end)}',
                  ),
                  onTap: _pickDates,
                ),
                TextField(
                  controller: _loc,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Location', hintText: 'City or venue'),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _booth,
                        decoration: const InputDecoration(labelText: 'Booth or table'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _goal,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Contact goal'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: d.autoScan,
                  onChanged: (v) => setState(() => d.autoScan = v),
                  title: const Text('Start a scan session automatically'),
                  subtitle: const Text('On each event day, the first time you open CardKeep.'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Follow-up reminder'),
                  subtitle: Text('${d.reminderOffsetDays} day${d.reminderOffsetDays == 1 ? '' : 's'} after it ends'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'One day sooner',
                        icon: const Icon(Icons.remove),
                        onPressed: d.reminderOffsetDays > 0 ? () => setState(() => d.reminderOffsetDays--) : null,
                      ),
                      IconButton(
                        tooltip: 'One day later',
                        icon: const Icon(Icons.add),
                        onPressed: d.reminderOffsetDays < 30 ? () => setState(() => d.reminderOffsetDays++) : null,
                      ),
                    ],
                  ),
                ),
                TextField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                if (widget.id != null) ...[
                  const SizedBox(height: 20),
                  TextButton.icon(
                    onPressed: _delete,
                    icon: Icon(Icons.delete_outline, color: Tokens.hotFg),
                    label: Text('Delete event', style: TextStyle(color: Tokens.hotFg)),
                  ),
                ],
              ],
            ),
    );
  }
}

/// On the scanner: which event new cards go to, with a way to end it.
class ActiveEventChip extends ConsumerWidget {
  const ActiveEventChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(activeSessionProvider).value;
    if (a == null) return const SizedBox.shrink();
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: () async {
          final end = await confirm(
            context,
            title: 'End the scan session?',
            message: 'New cards stop going to ${a.event.name}.',
            action: 'End session',
          );
          if (end) await ref.read(eventsRepoProvider).endSession();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.event, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                '${a.event.name} · ${a.cards} card${a.cards == 1 ? '' : 's'}',
                style: AppText.label.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
