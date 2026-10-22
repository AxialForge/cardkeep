import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/contacts/contact_models.dart';
import '../../core/contacts/contacts_repository.dart';
import '../../core/db/tables.dart';
import '../../core/settings/settings_repository.dart';
import '../../core/vcard/vcard.dart';
import '../career/career_screens.dart';
import '../duplicates/merge_screen.dart';
import '../shared/sensitive_clipboard.dart';
import '../tags/tags_screen.dart';

/// Contact detail (mockup Detail.dc.html).
class ContactDetailScreen extends ConsumerWidget {
  final String id;
  const ContactDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(contactDetailProvider(id));
    return Scaffold(
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load contact: $e')),
        data: (d) => d == null
            ? Scaffold(
                appBar: AppBar(),
                body: const EmptyState(
                  icon: Icons.person_off_outlined,
                  title: 'Contact not found',
                  message: 'It may have been deleted.',
                ),
              )
            : _DetailBody(d),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  final ContactDetail d;
  const _DetailBody(this.d);

  String get _id => d.person.uuid;

  Future<void> _launch(BuildContext context, Future<bool> Function() action) async {
    if (!await action() && context.mounted) showMessage(context, 'No app on this phone can open that.');
  }

  Future<void> _share(WidgetRef ref) async {
    final repo = ref.read(contactsRepoProvider);
    final name = d.person.displayName.isEmpty ? 'contact' : d.person.displayName;
    final file = '${name.replaceAll(RegExp(r'[^\w\- ]'), '').trim()}.vcf';
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(writeVCard(repo.toExport(d)))),
            mimeType: 'text/vcard',
            name: file,
          ),
        ],
        fileNameOverrides: [file],
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Delete ${d.person.displayName}?',
      message: 'You can undo this for a few seconds.',
      action: 'Delete',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final repo = ref.read(contactsRepoProvider);
    final messenger = ScaffoldMessenger.of(context);
    await repo.delete(_id);
    if (!context.mounted) return;
    context.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted ${d.person.displayName}'),
          action: SnackBarAction(label: 'Undo', onPressed: () => repo.restore(_id)),
        ),
      );
  }

  Future<void> _webCheck(BuildContext context, WidgetRef ref, {bool retirement = false}) {
    final engine = ref.read(searchEngineProvider).value ?? SearchEngine.google;
    return _launch(
      context,
      () => ref.read(launcherProvider).webCheck(engine, [
        d.person.first,
        d.person.last,
        d.currentRole?.company ?? d.roles.firstOrNull?.company,
        if (retirement) 'retirement',
      ]),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final launcher = ref.read(launcherProvider);
    final role = d.currentRole;
    final initials = [d.person.first, d.person.last].where((s) => s.isNotEmpty).map((s) => s[0].toUpperCase()).join();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: CustomScrollView(
        slivers: [
          // Dark header with the action bar overlapping its bottom edge.
          SliverToBoxAdapter(
            child: Stack(
              children: [
                Column(
                  children: [
                    Container(
                      color: Tokens.strong,
                      padding: EdgeInsets.fromLTRB(
                        Tokens.gutter,
                        MediaQuery.paddingOf(context).top + 8,
                        Tokens.gutter,
                        74,
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              DiscButton(
                                icon: Icons.arrow_back,
                                tooltip: 'Back',
                                onDark: true,
                                onPressed: () => context.pop(),
                              ),
                              const Spacer(),
                              DiscButton(
                                icon: Icons.edit_outlined,
                                tooltip: 'Edit',
                                onDark: true,
                                onPressed: () => context.push('/contact/$_id/edit'),
                              ),
                              const SizedBox(width: 8),
                              PopupMenuButton<String>(
                                tooltip: 'More',
                                icon: Icon(Icons.more_horiz, color: Tokens.onStrong),
                                style: IconButton.styleFrom(
                                  backgroundColor: Tokens.onStrong.withValues(alpha: 0.12),
                                  fixedSize: const Size(46, 46),
                                ),
                                onSelected: (v) => switch (v) {
                                  'share' => _share(ref),
                                  'web' => _webCheck(context, ref),
                                  'delete' => _delete(context, ref),
                                  'nologo' => ref.read(contactsRepoProvider).setLogo(_id, null),
                                  'moved' => showJobChangeSheet(context, ref, personId: _id),
                                  'retired' => showRetireSheet(context, ref, _id),
                                  'unretire' => ref.read(careerRepoProvider).unretire(_id),
                                  _ => null,
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(value: 'share', child: Text('Share as vCard')),
                                  const PopupMenuItem(value: 'web', child: Text('Check on web')),
                                  const PopupMenuItem(value: 'moved', child: Text('Changed jobs…')),
                                  if (d.person.status == PersonStatus.retired)
                                    const PopupMenuItem(value: 'unretire', child: Text('Not retired'))
                                  else
                                    const PopupMenuItem(value: 'retired', child: Text('Mark retired…')),
                                  if (d.person.logoSha256 != null)
                                    const PopupMenuItem(value: 'nologo', child: Text('Remove logo')),
                                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Avatar(
                                initials.isEmpty ? '?' : initials,
                                size: 76,
                                dark: true,
                                image: d.person.logoSha256 == null
                                    ? null
                                    : ref.watch(imageStoreProvider).value?.logo(d.person.logoSha256!),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SelectableText(
                                      d.person.displayName.isEmpty ? '(No name)' : d.person.displayName,
                                      style: AppText.title.copyWith(color: Tokens.onStrong),
                                    ),
                                    if (role != null && role.title.isNotEmpty)
                                      Text(role.title, style: AppText.body.copyWith(color: Tokens.onStrongMuted)),
                                    if (role?.company != null)
                                      Text(role!.company!, style: AppText.bodyStrong.copyWith(color: Tokens.brass)),
                                    if (Pill.status(d.person.status) case final p?)
                                      Padding(padding: const EdgeInsets.only(top: 6), child: p),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 58),
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Panel(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _Action(
                          Icons.call_outlined,
                          'Call',
                          primary: true,
                          onTap: d.callTarget == null
                              ? null
                              : () => _launch(context, () => launcher.call(d.callTarget!.value)),
                        ),
                        _Action(
                          Icons.mail_outline,
                          'Email',
                          primary: true,
                          onTap: d.emailTarget == null
                              ? null
                              : () => _launch(context, () => launcher.email(d.emailTarget!.value)),
                        ),
                        _Action(
                          Icons.chat_bubble_outline,
                          'Message',
                          onTap: d.textTarget == null
                              ? null
                              : () => _launch(context, () => launcher.text(d.textTarget!.value)),
                        ),
                        _Action(Icons.ios_share, 'Share', onTap: () => _share(ref)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                children: [
                  DuplicateBanner(personId: d.person.uuid),
                  CareerBanner(personId: d.person.uuid),
                  if (d.cards.isNotEmpty) _CardImagesPanel(card: d.cards.first),
                  if (d.points.isNotEmpty) _PointsPanel(d: d, launch: (a) => _launch(context, a)),
                  _InfoPanel(d: d),
                  ContactTagsPanel(personId: d.person.uuid),
                  _ColleaguesPanel(personId: d.person.uuid),
                  _NotesPanel(d: d),
                  _CareerPanel(
                    d: d,
                    onWebCheck: () => _webCheck(context, ref, retirement: d.person.status == PersonStatus.retired),
                  ),
                  SuccessionCards(personId: d.person.uuid),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback? onTap;
  const _Action(this.icon, this.label, {this.primary = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Opacity(
            opacity: enabled ? 1 : 0.35,
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: primary ? Tokens.action : Tokens.selected, shape: BoxShape.circle),
                  child: Icon(icon, color: primary ? Tokens.onAction : Tokens.ink, size: 21),
                ),
                const SizedBox(height: 6),
                ExcludeSemantics(
                  child: Text(label, style: AppText.label.copyWith(color: Tokens.ink)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PointsPanel extends ConsumerWidget {
  final ContactDetail d;
  final void Function(Future<bool> Function()) launch;
  const _PointsPanel({required this.d, required this.launch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.read(launcherProvider);
    final rows = <Widget>[];
    for (final p in d.points) {
      // An extension is dialled after a pause: "+14405100108,112".
      final dial = p.extension.isEmpty ? p.value : '${p.value},${p.extension}';
      final (icon, label, action) = switch (p.kind) {
        ContactKind.mobile => (Icons.smartphone, p.label.isEmpty ? 'Mobile' : p.label, () => l.call(dial)),
        ContactKind.office => (Icons.call_outlined, p.label.isEmpty ? 'Office' : p.label, () => l.call(dial)),
        ContactKind.fax => (Icons.print_outlined, 'Fax', () async => false),
        ContactKind.email => (Icons.mail_outline, 'Email', () => l.email(p.value)),
        ContactKind.web => (Icons.language, 'Website', () => l.web(p.value)),
        ContactKind.address => (Icons.place_outlined, 'Address', () => l.map(p.value)),
      };
      final isPhone = p.kind == ContactKind.mobile || p.kind == ContactKind.office || p.kind == ContactKind.fax;
      final ext = p.extension.isEmpty ? '' : ' ext. ${p.extension}';
      final shown = isPhone ? '${formatPhone(p.value)}$ext' : p.value;
      final suffix = switch (p.status) {
        ContactStatus.former => ' · former',
        ContactStatus.bounced => ' · bounced',
        ContactStatus.active => '',
      };
      if (rows.isNotEmpty) rows.add(const Divider(indent: 68));
      rows.add(
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: Tokens.selected, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20),
          ),
          title: Text('$label$suffix', style: AppText.secondary),
          subtitle: Text(
            shown,
            style: AppText.bodyStrong.copyWith(
              fontSize: 16,
              color: p.isActive ? Tokens.ink : Tokens.ink2,
              decoration: p.isActive ? null : TextDecoration.lineThrough,
            ),
          ),
          // Former/bounced points stay visible as history but are not one-tap targets.
          // Faxes are shown and copied (long-press), never dialled.
          onTap: p.isActive && p.kind != ContactKind.fax ? () => launch(action) : null,
          onLongPress: () async {
            // Active emails can also be marked as bounced (S12.1); everything copies.
            final bounce = p.kind == ContactKind.email && p.isActive
                ? await showModalBottomSheet<bool>(
                    context: context,
                    builder: (c) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.copy),
                            title: const Text('Copy'),
                            onTap: () => Navigator.pop(c, false),
                          ),
                          ListTile(
                            leading: const Icon(Icons.mark_email_unread_outlined),
                            title: const Text('Mark as bounced'),
                            subtitle: const Text(
                              'It is kept as history and no longer used; you can check if they moved.',
                            ),
                            onTap: () => Navigator.pop(c, true),
                          ),
                        ],
                      ),
                    ),
                  )
                : false;
            if (bounce == null) return;
            if (bounce) {
              await ref.read(careerRepoProvider).markBounced(p.id);
              return;
            }
            await copySensitive(shown);
            if (context.mounted) showMessage(context, 'Copied');
          },
        ),
      );
    }
    return Panel(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: rows),
    );
  }
}

class _InfoPanel extends ConsumerWidget {
  final ContactDetail d;
  const _InfoPanel({required this.d});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(contactsRepoProvider);
    final p = d.person;
    final due = p.followupAt;
    final done = p.followupDoneAt != null;
    String? dueText;
    if (due != null) {
      final days = DateUtils.dateOnly(due).difference(DateUtils.dateOnly(DateTime.now())).inDays;
      final rel = days == 0
          ? 'Today'
          : days == 1
          ? 'Tomorrow'
          : days > 0
          ? 'In $days days'
          : '${-days} days overdue';
      dueText = '${DateFormat('EEE, MMM d').format(due)} · ${done ? 'Done' : rel}';
    }

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d.metEventName != null) ...[
            InkWell(onTap: () => context.push('/event/${p.metEventId}'), child: _kv('Met at', d.metEventName!)),
            const SizedBox(height: 12),
          ],
          if (d.introducedByName != null) ...[_kv('Introduced by', d.introducedByName!), const SizedBox(height: 12)],
          for (final e in d.extras) ...[
            _kv(e.label.isEmpty ? 'From the card' : e.label, e.value),
            const SizedBox(height: 12),
          ],
          if (ref.watch(leadsEnabledProvider).value ?? true) ...[
            Text('Lead rating', style: AppText.secondary),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final r in LeadRating.values)
                  ChoiceChip(
                    label: Text(ratingLabel(r)),
                    selected: p.leadRating == r,
                    showCheckmark: false,
                    onSelected: (on) => repo.setLeadRating(p.uuid, on ? r : null),
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          Text('Follow up', style: AppText.secondary),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  dueText ?? 'Not set',
                  style: AppText.bodyStrong.copyWith(
                    color: due != null && !done && due.isBefore(DateTime.now()) ? Tokens.hotFg : Tokens.ink,
                  ),
                ),
              ),
              if (due != null && !done)
                TextButton(onPressed: () => repo.markFollowupDone(p.uuid), child: const Text('Done')),
              TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: due ?? DateTime.now().add(const Duration(days: 7)),
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                  );
                  if (picked != null) {
                    await repo.setFollowup(p.uuid, DateTime(picked.year, picked.month, picked.day, 8));
                  }
                },
                child: Text(due == null ? 'Set' : 'Change'),
              ),
              if (due != null)
                IconButton(
                  tooltip: 'Clear follow-up',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => repo.setFollowup(p.uuid, null),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(k, style: AppText.secondary),
      Text(v, style: AppText.bodyStrong),
    ],
  );
}

class _NotesPanel extends ConsumerWidget {
  final ContactDetail d;
  const _NotesPanel({required this.d});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final ctl = TextEditingController();
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(c).bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add a note', style: AppText.heading),
            const SizedBox(height: 4),
            Text('Saved with today\'s date at the top of the notes.', style: AppText.secondary),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              autofocus: true,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Called, wants a quote'),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('Save note')),
          ],
        ),
      ),
    );
    ctl.dispose();
    if (text != null && text.trim().isNotEmpty) await ref.read(contactsRepoProvider).addNote(d.person.uuid, text);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: Overline('Notes')),
            TextButton.icon(
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add note'),
            ),
          ],
        ),
        if (d.person.notes.isEmpty)
          Text('No notes yet.', style: AppText.secondary)
        else
          SelectableText(d.person.notes, style: AppText.body),
      ],
    ),
  );
}

class _CareerPanel extends StatelessWidget {
  final ContactDetail d;
  final VoidCallback onWebCheck;
  const _CareerPanel({required this.d, required this.onWebCheck});

  String _years(RoleView r) {
    final s = r.startDate?.year;
    final e = r.endDate?.year;
    if (s == null && e == null) return '';
    if (s == null) return ' (until $e)';
    return ' ($s to ${e ?? 'now'})';
  }

  @override
  Widget build(BuildContext context) {
    final current = d.currentRole;
    final former = d.roles.where((r) => r.status != RoleStatus.current);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Overline('Career')),
              Pill(
                d.person.trackCareer ? 'TRACKING ON' : 'TRACKING OFF',
                bg: d.person.trackCareer ? Tokens.amberBg : Tokens.selected,
                fg: d.person.trackCareer ? Tokens.amberFg : Tokens.ink2,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (current != null)
            Text(
              [current.title, current.company].where((s) => s != null && s.isNotEmpty).join(', '),
              style: AppText.bodyStrong,
            )
          else
            Text('No current role', style: AppText.secondary),
          for (final r in former)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Previously: ${[r.title, r.company].where((s) => s != null && s.isNotEmpty).join(', ')}${_years(r)}',
                style: AppText.secondary,
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onWebCheck,
            icon: const Icon(Icons.travel_explore, size: 20),
            label: const Text('Check on web'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 44)),
          ),
          const SizedBox(height: 6),
          Text('Web check opens in your default browser.', style: AppText.secondary.copyWith(fontSize: 12)),
        ],
      ),
    );
  }
}

/// Front/back of the newest scanned card (mockup Detail: Front | Back). Tap to zoom.
class _CardImagesPanel extends ConsumerStatefulWidget {
  final CardView card;
  const _CardImagesPanel({required this.card});
  @override
  ConsumerState<_CardImagesPanel> createState() => _CardImagesPanelState();
}

class _CardImagesPanelState extends ConsumerState<_CardImagesPanel> {
  bool _back = false;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(imageStoreProvider).value;
    final c = widget.card;
    final hash = _back && c.backHash != null ? c.backHash! : c.frontHash;
    final file = store?.rectified(hash);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (c.backHash != null)
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('Front')),
                    ButtonSegment(value: true, label: Text('Back')),
                  ],
                  selected: {_back},
                  onSelectionChanged: (v) => setState(() => _back = v.single),
                ),
              const Spacer(),
              Text('Scanned ${DateFormat('MMM d, y').format(c.scannedAt)}', style: AppText.secondary),
            ],
          ),
          const SizedBox(height: 12),
          if (file != null && file.existsSync())
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => Scaffold(
                    backgroundColor: Colors.black,
                    appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
                    body: InteractiveViewer(maxScale: 6, child: Center(child: Image.file(file))),
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Tokens.radiusSm),
                child: Image.file(file, fit: BoxFit.contain, semanticLabel: _back ? 'Back of card' : 'Front of card'),
              ),
            )
          else
            Text('Card image not on this device.', style: AppText.secondary),
        ],
      ),
    );
  }
}

/// "Others at Halden Tooling": people at the same company (S10b.6).
class _ColleaguesPanel extends ConsumerWidget {
  final String personId;
  const _ColleaguesPanel({required this.personId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(colleaguesProvider(personId)).value;
    if (data == null || data.$2.isEmpty) return const SizedBox.shrink();
    final (company, people) = data;
    return Panel(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Overline('Others at $company (${people.length})'),
          ),
          for (final c in people.take(8))
            ListTile(
              dense: true,
              leading: Avatar(c.initials, size: 36),
              title: Text(c.displayName, style: AppText.bodyStrong),
              subtitle: c.title == null || c.title!.isEmpty ? null : Text(c.title!, style: AppText.secondary),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/contact/${c.id}'),
            ),
          if (people.length > 8)
            TextButton(
              onPressed: () {
                ref.read(contactFilterProvider.notifier).set(ContactFilter(query: company, sort: ContactSort.company));
                context.go('/');
              },
              child: Text('Show all ${people.length}'),
            ),
        ],
      ),
    );
  }
}
