import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/drawer.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/career/career_repository.dart';
import '../../core/contacts/contact_models.dart';
import '../../core/db/database.dart';

final pendingCareerProvider = StreamProvider<List<CareerSuggestion>>(
  (ref) => ref.watch(careerRepoProvider).watchPending(),
);
final pendingCareerForProvider = StreamProvider.family<List<CareerSuggestion>, String>(
  (ref, id) => ref.watch(careerRepoProvider).watchPending(personId: id),
);
final recentCareerProvider = StreamProvider<List<(PersonRef, PersonStatus, DateTime)>>(
  (ref) => ref.watch(careerRepoProvider).watchRecent(),
);
final successionProvider = StreamProvider.family<SuccessionView, String>(
  (ref, id) => ref.watch(careerRepoProvider).watchSuccession(id),
);

/// Career moves (mockup Career, S12.2): possible changes to confirm and
/// recent moves and retirements.
class CareerScreen extends ConsumerWidget {
  const CareerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingCareerProvider).value ?? const <CareerSuggestion>[];
    final recent = ref.watch(recentCareerProvider).value ?? const [];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Tokens.groundOverlay,
      child: Scaffold(
        drawer: const AppDrawer(current: '/career'),
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
                child: Text('Career moves', style: AppText.display),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'When a new card shows someone at another company, or an email bounces, it shows here to confirm.',
                  style: AppText.secondary,
                ),
              ),
              if (pending.isEmpty && recent.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: EmptyState(
                    icon: Icons.swap_horiz,
                    title: 'Nothing to check',
                    message: 'Job changes and retirements you confirm are listed here.',
                  ),
                ),
              if (pending.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Overline('To confirm (${pending.length})'),
                ),
                for (final s in pending) SuggestionCard(s),
              ],
              if (recent.isNotEmpty) ...[
                const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 0), child: Overline('Recent changes')),
                Panel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (p, status, at) in recent)
                        ListTile(
                          title: Text(p.name, style: AppText.bodyStrong),
                          subtitle: Text(
                            '${status == PersonStatus.retired ? 'Retired' : 'Moved'} · ${DateFormat('MMM d, y').format(at)}',
                            style: AppText.secondary,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/contact/${p.id}'),
                        ),
                    ],
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

/// One pending suggestion with what to do about it.
class SuggestionCard extends ConsumerWidget {
  final CareerSuggestion s;
  final bool showName;
  const SuggestionCard(this.s, {super.key, this.showName = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(careerRepoProvider);
    final (icon, text) = switch (s.kind) {
      SuggestionKind.moved => (
        Icons.swap_horiz,
        s.newCompany == null ? 'May have changed jobs' : 'A new card shows them at ${s.newCompany}',
      ),
      SuggestionKind.bounce => (Icons.mark_email_unread_outlined, 'Email bounced: ${s.payload['email'] ?? ''}'),
      SuggestionKind.retired => (Icons.beach_access_outlined, 'May have retired'),
    };
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: Tokens.amberFg),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showName)
                      InkWell(
                        onTap: () => context.push('/contact/${s.personId}'),
                        child: Text(s.personName, style: AppText.bodyStrong),
                      ),
                    Text(text, style: AppText.secondary),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            children: [
              TextButton(onPressed: () => repo.dismiss(s.id), child: const Text('Dismiss')),
              if (s.kind != SuggestionKind.moved)
                TextButton(onPressed: () => showRetireSheet(context, ref, s.personId), child: const Text('Retired')),
              FilledButton(
                onPressed: () => showJobChangeSheet(context, ref, personId: s.personId, suggestion: s),
                child: Text(s.kind == SuggestionKind.moved ? 'Review' : 'Moved jobs'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pending suggestions for one person, on their page.
class CareerBanner extends ConsumerWidget {
  final String personId;
  const CareerBanner({super.key, required this.personId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(pendingCareerForProvider(personId)).value ?? const [];
    return Column(children: [for (final s in list) SuggestionCard(s, showName: false)]);
  }
}

/// "Replaced by" on a predecessor, "Replaces" on a successor (S12.7).
class SuccessionCards extends ConsumerWidget {
  final String personId;
  const SuccessionCards({super.key, required this.personId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(successionProvider(personId)).value;
    if (v == null || (v.replacedBy == null && v.replaces.isEmpty)) return const SizedBox.shrink();
    final launcher = ref.read(launcherProvider);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (v.replacedBy case final next?) ...[
            Overline(
              'Replaced by${v.replacedByRole == null || v.replacedByRole!.isEmpty ? '' : ' as ${v.replacedByRole}'}',
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(next.name, style: AppText.bodyStrong),
              subtitle: next.company == null ? null : Text(next.company!, style: AppText.secondary),
              onTap: () => context.push('/contact/${next.id}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (next.phone != null)
                    IconButton(
                      tooltip: 'Call ${next.name}',
                      icon: const Icon(Icons.call_outlined),
                      onPressed: () => launcher.call(next.phone!),
                    ),
                  if (next.email != null)
                    IconButton(
                      tooltip: 'Email ${next.name}',
                      icon: const Icon(Icons.mail_outline),
                      onPressed: () => launcher.email(next.email!),
                    ),
                ],
              ),
            ),
          ],
          if (v.replaces.isNotEmpty) ...[
            const Overline('Replaces'),
            for (final p in v.replaces)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(p.name, style: AppText.bodyStrong),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/contact/${p.id}'),
              ),
          ],
        ],
      ),
    );
  }
}

/// Picks another contact (successor). Returns the id, or null.
Future<String?> pickPerson(BuildContext context, {required String title, String? exclude}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PersonPicker(title: title, exclude: exclude),
    );

class _PersonPicker extends ConsumerStatefulWidget {
  final String title;
  final String? exclude;
  const _PersonPicker({required this.title, this.exclude});
  @override
  ConsumerState<_PersonPicker> createState() => _PersonPickerState();
}

class _PersonPickerState extends ConsumerState<_PersonPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(contactsRepoProvider);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(widget.title, style: AppText.heading),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search contacts'),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<ContactSummary>>(
                stream: repo.watchContacts(ContactFilter(query: _q)),
                builder: (_, snap) => ListView(
                  children: [
                    for (final c in (snap.data ?? const <ContactSummary>[]).where((c) => c.id != widget.exclude))
                      ListTile(
                        leading: Avatar(c.initials, size: 36),
                        title: Text(c.displayName, style: AppText.bodyStrong),
                        subtitle: c.subtitle.isEmpty ? null : Text(c.subtitle, style: AppText.secondary),
                        onTap: () => Navigator.pop(context, c.id),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Possible job change / "Mark as moved" (mockup JobChange, S12.3).
Future<void> showJobChangeSheet(
  BuildContext context,
  WidgetRef ref, {
  required String personId,
  CareerSuggestion? suggestion,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _JobChangeSheet(personId: personId, suggestion: suggestion),
);

class _JobChangeSheet extends ConsumerStatefulWidget {
  final String personId;
  final CareerSuggestion? suggestion;
  const _JobChangeSheet({required this.personId, this.suggestion});
  @override
  ConsumerState<_JobChangeSheet> createState() => _JobChangeSheetState();
}

class _JobChangeSheetState extends ConsumerState<_JobChangeSheet> {
  JobChange _choice = JobChange.keepHistory;
  late final _company = TextEditingController(text: widget.suggestion?.newCompany ?? '');
  late final _title = TextEditingController(text: widget.suggestion?.newTitle ?? '');
  String? _successor;
  String? _successorName;
  bool _moveFollowup = true;

  bool get _fromCard => widget.suggestion?.newPersonId != null;

  @override
  void dispose() {
    _company.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final repo = ref.read(careerRepoProvider);
    final s = widget.suggestion;
    if (!_fromCard && _choice != JobChange.different && _company.text.trim().isEmpty) {
      showMessage(context, 'Where do they work now?');
      return;
    }
    if (s != null) {
      await repo.resolveMove(
        s,
        _choice,
        company: _fromCard ? null : _company.text.trim(),
        title: _fromCard ? null : _title.text.trim(),
        successorId: _successor,
      );
    } else if (_choice != JobChange.different) {
      final old = (await ref.read(contactsRepoProvider).loadDetail(widget.personId))?.currentRole;
      await repo.changeJob(
        widget.personId,
        company: _company.text.trim(),
        title: _title.text.trim(),
        replace: _choice == JobChange.replace,
      );
      if (_successor != null) await repo.addSuccession(widget.personId, _successor!, roleTitle: old?.title ?? '');
    }
    if (_successor != null && _moveFollowup) await repo.moveFollowup(widget.personId, _successor!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(contactDetailProvider(widget.personId)).value;
    final oldCompany = d?.currentRole?.company;
    final hasFollowup = d?.person.followupAt != null && d?.person.followupDoneAt == null;
    Widget option(JobChange c, String title, String sub) => RadioListTile<JobChange>(
      value: c,
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: AppText.bodyStrong),
      subtitle: Text(sub, style: AppText.secondary),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.suggestion == null ? 'Changed jobs' : 'Possible job change', style: AppText.heading),
            if (d != null)
              Text('${d.person.displayName}${oldCompany == null ? '' : ', at $oldCompany'}', style: AppText.secondary),
            const SizedBox(height: 8),
            if (!_fromCard) ...[
              TextField(
                controller: _company,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'New company'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'New title'),
              ),
              const SizedBox(height: 6),
            ],
            RadioGroup<JobChange>(
              groupValue: _choice,
              onChanged: (v) => setState(() => _choice = v!),
              child: Column(
                children: [
                  option(
                    JobChange.keepHistory,
                    'Add as new role, keep history',
                    'The old job and work email stay as history.',
                  ),
                  option(JobChange.replace, 'Replace old details', 'The old job and work email are removed.'),
                  if (widget.suggestion != null)
                    option(
                      JobChange.different,
                      'Different person',
                      'Nothing changes; this pair is not suggested again.',
                    ),
                ],
              ),
            ),
            if (_choice != JobChange.different && oldCompany != null) ...[
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_search_outlined),
                title: Text(_successorName ?? 'Who took over at $oldCompany?'),
                subtitle: const Text('Optional'),
                trailing: _successor == null
                    ? const Icon(Icons.chevron_right)
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _successor = _successorName = null),
                      ),
                onTap: () async {
                  final id = await pickPerson(context, title: 'Their replacement', exclude: widget.personId);
                  if (id == null) return;
                  final p = await ref.read(contactsRepoProvider).loadDetail(id);
                  setState(() {
                    _successor = id;
                    _successorName = p?.person.displayName;
                  });
                },
              ),
              if (_successor != null && hasFollowup)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _moveFollowup,
                  onChanged: (v) => setState(() => _moveFollowup = v ?? false),
                  title: Text('Move the follow-up to ${_successorName ?? 'them'}'),
                ),
            ],
            const SizedBox(height: 12),
            FilledButton(onPressed: _apply, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}

/// Mark retired (mockup Retired, S12.5), with an optional replacement.
Future<void> showRetireSheet(BuildContext context, WidgetRef ref, String personId) async {
  final d = await ref.read(contactsRepoProvider).loadDetail(personId);
  if (!context.mounted || d == null) return;
  final successor = await pickPerson(
    context,
    title:
        'Who replaced ${d.person.first.isEmpty ? 'them' : d.person.first}${d.currentRole?.company == null ? '' : ' at ${d.currentRole!.company}'}? (optional, close to skip)',
    exclude: personId,
  );
  if (!context.mounted) return;
  final ok = await confirm(
    context,
    title: 'Mark ${d.person.displayName} as retired?',
    message: successor == null
        ? 'Their job is kept as history. You can undo this from their page.'
        : 'Their job is kept as history and their replacement is linked. Any open follow-up moves to the replacement.',
    action: 'Mark retired',
  );
  if (!ok) return;
  final repo = ref.read(careerRepoProvider);
  await repo.retire(personId, successorId: successor);
  if (successor != null) await repo.moveFollowup(personId, successor);
}
