import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/plural.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/contacts/contact_models.dart';
import '../../core/contacts/contacts_repository.dart';
import '../../core/contacts/place_category_repository.dart';
import '../../core/db/tables.dart';
import '../../scan/scan_pipeline.dart';
import '../desktop/desktop_providers.dart';
import '../events/events_screens.dart';
import '../scan/review_panel.dart';
import '../scan/scan_review.dart';

const phoneLabels = ['Mobile', 'Office', 'Direct', 'Fax', 'Other'];
final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

/// New and edit contact (mockup ContactEdit.dc.html). [id] null = new contact.
class ContactEditScreen extends ConsumerStatefulWidget {
  final String? id;

  /// A scanned card to prefill from (new contacts only).
  final ScanHandoff? scan;

  /// Details from an NFC tap card (new contacts only, S14).
  final ContactDraft? prefill;
  const ContactEditScreen({super.key, this.id, this.scan, this.prefill});

  @override
  ConsumerState<ContactEditScreen> createState() => _ContactEditScreenState();
}

class _PhoneRow {
  String label;
  final TextEditingController ctl;
  final TextEditingController ext;
  _PhoneRow(this.label, String value, [String extension = ''])
    : ctl = TextEditingController(text: value),
      ext = TextEditingController(text: extension);

  void dispose() {
    ctl.dispose();
    ext.dispose();
  }
}

/// One "more from the card" line: what it is and the text.
class _ExtraRow {
  final TextEditingController label, value;
  _ExtraRow(String l, String v) : label = TextEditingController(text: l), value = TextEditingController(text: v);
  void dispose() {
    label.dispose();
    value.dispose();
  }
}

class _ContactEditScreenState extends ConsumerState<ContactEditScreen> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _middle = TextEditingController();
  final _last = TextEditingController();
  bool _showMiddle = false;
  final _extras = <_ExtraRow>[];
  final _title = TextEditingController();
  final _company = TextEditingController();
  final _website = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final _hours = TextEditingController();
  PersonKind _kind = PersonKind.person;
  String? _category; // a place_categories id
  final _phones = <_PhoneRow>[];
  final _emails = <TextEditingController>[];
  LeadRating? _rating;
  DateTime? _followup;
  bool _trackCareer = true;
  bool _loading = true;
  bool _saving = false;
  ContactDraft? _original;
  Set<String> _check = const {}; // fields the parser was unsure about

  bool get _isNew => widget.id == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var draft = ContactDraft(phones: [const LabeledValue('Mobile', '')], emails: ['']);
    if (!_isNew) {
      final d = await ref.read(contactsRepoProvider).loadDetail(widget.id!);
      if (d != null) draft = d.toDraft();
    } else if (widget.scan != null) {
      final s = widget.scan!;
      draft = draftFromScan(s.front.parsed, s.back?.parsed);
      _check = s.front.check;
    } else if (widget.prefill != null) {
      draft = widget.prefill!;
      if (draft.phones.isEmpty) draft.phones = [const LabeledValue('Mobile', '')];
      if (draft.emails.isEmpty) draft.emails = [''];
    }
    if (!mounted) return;
    _first.text = draft.first;
    _middle.text = draft.middle;
    _showMiddle = draft.middle.isNotEmpty;
    _last.text = draft.last;
    _extras.addAll(draft.extras.map((e) => _ExtraRow(e.label, e.value)));
    _title.text = draft.title;
    _company.text = draft.company;
    _website.text = draft.website;
    _address.text = draft.address;
    _notes.text = draft.notes;
    _hours.text = draft.hours;
    _kind = draft.kind;
    _category = draft.category;
    for (final p in draft.phones) {
      _phones.add(_PhoneRow(phoneLabels.contains(p.label) ? p.label : 'Other', formatPhone(p.value), p.ext));
    }
    for (final f in draft.faxes) {
      _phones.add(_PhoneRow('Fax', formatPhone(f.value), f.ext));
    }
    if (_phones.isEmpty) _phones.add(_PhoneRow('Mobile', ''));
    _emails.addAll(draft.emails.map((e) => TextEditingController(text: e)));
    if (_emails.isEmpty) _emails.add(TextEditingController());
    _rating = draft.leadRating;
    _followup = draft.followupAt;
    _trackCareer = draft.trackCareer;
    _original = _draft();
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final c in [_first, _middle, _last, _title, _company, _website, _address, _notes, _hours, ..._emails]) {
      c.dispose();
    }
    for (final p in _phones) {
      p.dispose();
    }
    for (final e in _extras) {
      e.dispose();
    }
    super.dispose();
  }

  ContactDraft _draft() => ContactDraft(
    first: _first.text,
    middle: _middle.text,
    last: _last.text,
    title: _title.text,
    company: _company.text,
    phones: [
      for (final p in _phones)
        if (p.ctl.text.trim().isNotEmpty && p.label != 'Fax')
          LabeledValue(p.label, p.ctl.text.trim(), p.ext.text.trim()),
    ],
    faxes: [
      for (final p in _phones)
        if (p.ctl.text.trim().isNotEmpty && p.label == 'Fax') LabeledValue('Fax', p.ctl.text.trim(), p.ext.text.trim()),
    ],
    extras: [
      for (final e in _extras)
        if (e.value.text.trim().isNotEmpty) LabeledValue(e.label.text.trim(), e.value.text.trim()),
    ],
    emails: [
      for (final e in _emails)
        if (e.text.trim().isNotEmpty) e.text.trim(),
    ],
    website: _website.text,
    address: _address.text,
    notes: _notes.text,
    leadRating: _rating,
    followupAt: _followup,
    trackCareer: _trackCareer,
    kind: _kind,
    category: _category,
    hours: _hours.text,
  );

  bool get _isPlace => _kind == PersonKind.place;

  bool get _dirty {
    final a = _original, b = _draft();
    if (a == null) return false;
    String sig(ContactDraft d) => [
      d.first,
      d.middle,
      d.last,
      d.title,
      d.company,
      d.website,
      d.address,
      d.notes,
      d.leadRating,
      d.followupAt,
      d.trackCareer,
      d.kind,
      d.category,
      d.hours,
      d.phones.map((p) => '${p.label}:${p.value}:${p.ext}').join('|'),
      d.faxes.map((p) => '${p.value}:${p.ext}').join('|'),
      d.extras.map((e) => '${e.label}:${e.value}').join('|'),
      d.emails.join('|'),
    ].join('\u0000');
    return sig(a) != sig(b);
  }

  /// "+ New" on the category chips: adds a category and picks it (S14b.6).
  Future<void> _newCategory() async {
    final name = await askText(context, title: 'New category', action: 'Add');
    if (name == null) return;
    final id = await ref.read(placeCategoryRepoProvider).add(name);
    if (mounted) setState(() => _category = id);
  }

  Future<void> _save({bool next = false}) async {
    if (!_form.currentState!.validate()) return;
    final d = _draft();
    if (d.isEmpty) {
      showMessage(
        context,
        _isPlace ? 'Add the business name, a phone or an email.' : 'Add at least a name, company, phone or email.',
      );
      return;
    }
    setState(() => _saving = true);
    final region = ref.read(regionProvider).value ?? 'US';
    final repo = ref.read(contactsRepoProvider);
    final id = await repo.save(
      d,
      id: widget.id,
      region: region,
      source: widget.scan != null
          ? RoleSource.scan
          : widget.prefill != null
          ? RoleSource.nfcLink
          : RoleSource.manual,
    );
    final scan = widget.scan;
    if (scan != null) {
      await (await ref.read(cardQueueProvider.future)).link(scan.cardId, id);
      // A new card for someone already here, at another company: a possible job change (S12).
      if (_isNew && !d.isPlace) await ref.read(careerRepoProvider).checkNewCard(id);
    } else if (widget.prefill != null && _isNew) {
      // A tapped card: the open event session applies, then the job-change check (S14.10).
      final session = await ref.read(eventsRepoProvider).watchActive().first;
      if (session != null) await ref.read(eventsRepoProvider).setMetAt(id, session.event.uuid);
      if (!d.isPlace) await ref.read(careerRepoProvider).checkNewCard(id);
    }
    if (!mounted) return;
    _original = d;
    if (scan != null && next) {
      // "Save and review next": straight into the next card waiting in the queue.
      final waiting = (await ref.read(cardQueueProvider.future).then((q) => q.watchQueue().first))
          .where((i) => i.cardId != scan.cardId)
          .toList();
      if (!mounted) return;
      if (waiting.isNotEmpty) {
        final n = waiting.first;
        context.pushReplacement(
          '/contact/new',
          extra: ScanHandoff(cardId: n.cardId, front: n.front, back: n.back),
        );
        return;
      }
      showMessage(context, 'Saved. That was the last card to review.');
    }
    if (_isNew) {
      context.pushReplacement('/contact/$id');
    } else {
      context.pop();
    }
  }

  /// Puts a piece of card text into the chosen field (review screen).
  void _assign(CardField f, String text) {
    final t = text.trim();
    setState(() {
      switch (f) {
        case CardField.name when _isPlace:
          _company.text = t; // a place's name is its business name
        case CardField.name:
          final parts = t.split(RegExp(r'\s+'));
          _first.text = parts.first;
          _middle.text = parts.length > 2 ? parts.sublist(1, parts.length - 1).join(' ') : '';
          if (_middle.text.isNotEmpty) _showMiddle = true;
          _last.text = parts.length > 1 ? parts.last : '';
        case CardField.title:
          _title.text = t;
        case CardField.company:
          _company.text = t;
        case CardField.website:
          _website.text = t;
        case CardField.address:
          _address.text = t;
        case CardField.notes:
          _notes.text = _notes.text.isEmpty ? t : '${_notes.text}\n$t';
        case CardField.phone:
          final empty = _phones.where((p) => p.ctl.text.trim().isEmpty).firstOrNull;
          if (empty != null) {
            empty.ctl.text = t;
          } else {
            _phones.add(_PhoneRow('Office', t));
          }
        case CardField.email:
          final empty = _emails.where((e) => e.text.trim().isEmpty).firstOrNull;
          if (empty != null) {
            empty.text = t.toLowerCase();
          } else {
            _emails.add(TextEditingController(text: t.toLowerCase()));
          }
      }
      _check = {..._check}..remove(f == CardField.phone ? 'phone' : f.name);
    });
  }

  /// Removes the scanned card from the queue (with undo) and leaves.
  Future<void> _discardCard() async {
    final scan = widget.scan!;
    final messenger = ScaffoldMessenger.of(context);
    final queue = await ref.read(cardQueueProvider.future);
    await queue.discard(scan.cardId);
    _original = _draft();
    if (!mounted) return;
    context.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Card removed'),
          duration: const Duration(seconds: 5),
          persist: false, // an Undo message otherwise never goes away (F37)
          action: SnackBarAction(label: 'Undo', onPressed: () => queue.restore(scan.cardId)),
        ),
      );
  }

  Future<void> _maybeLeave() async {
    if (!_dirty ||
        await confirm(
          context,
          title: 'Discard changes?',
          message: 'Your edits will be lost.',
          action: 'Discard',
          destructive: true,
        )) {
      _original = _draft();
      // A scanned card that isn't saved stays in the review queue.
      if (widget.scan != null && mounted) showMessage(context, 'Kept in the review queue');
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    ref.listen(saveRequestProvider, (_, _) => _save()); // Ctrl+S on Windows
    final region = ref.watch(regionProvider).value ?? 'US';
    final repo = ref.read(contactsRepoProvider);
    final leads = ref.watch(leadsEnabledProvider).value ?? true;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Tokens.groundOverlay,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _maybeLeave();
        },
        child: Scaffold(
          body: SafeArea(
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Tokens.gutter, 8, Tokens.gutter, 0),
                    child: Row(
                      children: [
                        DiscButton(icon: Icons.arrow_back, tooltip: 'Back', onPressed: _maybeLeave),
                        const Spacer(),
                        PopupMenuButton<String>(
                          tooltip: 'More options',
                          icon: const Icon(Icons.more_vert),
                          onSelected: (v) {
                            if (v == 'leads') ref.read(settingsRepoProvider).setLeadsEnabled(!leads);
                          },
                          itemBuilder: (_) => [
                            CheckedPopupMenuItem(value: 'leads', checked: leads, child: const Text('Lead ratings')),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.scan != null
                                    ? 'Review scan'
                                    : _isPlace
                                    ? (_isNew ? 'New place' : 'Edit place')
                                    : (_isNew ? 'New contact' : 'Edit contact'),
                                style: AppText.display,
                              ),
                            ),
                            if (widget.scan != null && _check.isNotEmpty)
                              Pill('${_check.length} to check', bg: Tokens.amberBg, fg: Tokens.amberFg),
                          ],
                        ),
                        if (widget.scan != null)
                          Text(switch (ref.watch(queueProvider).value?.length ?? 1) {
                            <= 1 => 'Last card to review',
                            final n => '${plural(n, 'card')} waiting to review',
                          }, style: AppText.secondary),
                        if (!_isNew && _original!.displayName.isNotEmpty)
                          Text(_original!.displayName, style: AppText.secondary),
                      ],
                    ),
                  ),
                  if (widget.scan != null) ...[
                    ReviewCardPanel(
                      side: widget.scan!.front,
                      onAssign: _assign,
                      addBackFor: widget.scan!.back == null ? widget.scan : null,
                    ),
                    if (widget.scan!.back != null) ReviewCardPanel(side: widget.scan!.back!, onAssign: _assign),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: Tokens.gutter),
                        child: TextButton.icon(
                          onPressed: _discardCard,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Remove this card'),
                        ),
                      ),
                    ),
                    if (widget.scan!.front.ocr == null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                        child: Text(
                          'Text reading is not available on this device; type the details from the card.',
                          style: AppText.secondary,
                        ),
                      ),
                  ],
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // A person, or a place: a store, restaurant, vendor or service card (S14b).
                        SegmentedButton<PersonKind>(
                          segments: const [
                            ButtonSegment(
                              value: PersonKind.person,
                              icon: Icon(Icons.person_outline),
                              label: Text('Person'),
                            ),
                            ButtonSegment(
                              value: PersonKind.place,
                              icon: Icon(Icons.storefront_outlined),
                              label: Text('Place'),
                            ),
                          ],
                          selected: {_kind},
                          showSelectedIcon: false,
                          onSelectionChanged: (s) => setState(() {
                            _kind = s.first;
                            // A person's name becomes the business name when there is none yet.
                            if (_isPlace && _company.text.trim().isEmpty) {
                              _company.text = [
                                _first.text,
                                _middle.text,
                                _last.text,
                              ].map((t) => t.trim()).where((t) => t.isNotEmpty).join(' ');
                            }
                          }),
                        ),
                        _gap,
                        if (_isPlace) ...[
                          _AutoField(
                            label: 'Business name',
                            controller: _company,
                            suggest: repo.companyNames,
                            check: _check.contains('company'),
                          ),
                          _gap,
                          Text('Category', style: AppText.label),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              for (final c in ref.watch(placeCategoriesProvider).value ?? const <PlaceCategoryItem>[])
                                ChoiceChip(
                                  label: Text(c.label),
                                  selected: _category == c.id,
                                  showCheckmark: false,
                                  onSelected: (on) => setState(() => _category = on ? c.id : null),
                                ),
                              ActionChip(
                                avatar: Icon(Icons.add, size: 18, color: Tokens.brass),
                                label: const Text('New'),
                                onPressed: _newCategory,
                              ),
                            ],
                          ),
                          _gap,
                          _field('Opening hours', _hours, maxLines: 3, cap: TextCapitalization.sentences),
                          _gap,
                        ],
                        if (!_isPlace) ...[
                          Row(
                            children: [
                              Expanded(
                                child: _field(
                                  'First name',
                                  _first,
                                  cap: TextCapitalization.words,
                                  autofocus: _isNew && widget.scan == null,
                                  check: _check.contains('name'),
                                ),
                              ),
                              if (_showMiddle) ...[
                                const SizedBox(width: 10),
                                SizedBox(width: 84, child: _field('Middle', _middle, cap: TextCapitalization.words)),
                              ],
                              const SizedBox(width: 10),
                              Expanded(
                                child: _field(
                                  'Last name',
                                  _last,
                                  cap: TextCapitalization.words,
                                  check: _check.contains('name'),
                                ),
                              ),
                            ],
                          ),
                          if (!_showMiddle)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: () => setState(() => _showMiddle = true),
                                child: const Text('Add middle name or initial'),
                              ),
                            ),
                          _gap,
                          _AutoField(
                            label: 'Title',
                            controller: _title,
                            suggest: repo.titles,
                            check: _check.contains('title'),
                          ),
                          _gap,
                          _AutoField(
                            label: 'Company',
                            controller: _company,
                            suggest: repo.companyNames,
                            check: _check.contains('company'),
                          ),
                          _gap,
                        ],
                        for (final (i, p) in _phones.indexed) ...[
                          _PhoneField(
                            row: p,
                            region: region,
                            onLabel: (l) => setState(() => p.label = l),
                            onRemove: _phones.length == 1
                                ? null
                                : () => setState(() {
                                    _phones.removeAt(i).dispose();
                                  }),
                          ),
                          _gap,
                        ],
                        _addButton('Add phone', () => setState(() => _phones.add(_PhoneRow('Office', '')))),
                        for (final (i, e) in _emails.indexed) ...[
                          Row(
                            children: [
                              Expanded(
                                child: _field(
                                  'Email',
                                  e,
                                  keyboard: TextInputType.emailAddress,
                                  check: _check.contains('email'),
                                  validator: (v) => v == null || v.trim().isEmpty || _emailRe.hasMatch(v.trim())
                                      ? null
                                      : 'That doesn\'t look like an email address',
                                ),
                              ),
                              if (_emails.length > 1)
                                IconButton(
                                  tooltip: 'Remove email',
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () => setState(() => _emails.removeAt(i).dispose()),
                                ),
                            ],
                          ),
                          _gap,
                        ],
                        _addButton('Add email', () => setState(() => _emails.add(TextEditingController()))),
                        Row(
                          children: [
                            Expanded(
                              child: _field(
                                'Website',
                                _website,
                                keyboard: TextInputType.url,
                                check: _check.contains('website'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton.outlined(
                              tooltip: 'Open in browser',
                              style: IconButton.styleFrom(
                                fixedSize: const Size(52, 52),
                                side: BorderSide(color: Tokens.hairline),
                              ),
                              icon: const Icon(Icons.language),
                              onPressed: () =>
                                  _website.text.trim().isEmpty ? null : ref.read(launcherProvider).web(_website.text),
                            ),
                          ],
                        ),
                        _gap,
                        _field(
                          'Address',
                          _address,
                          maxLines: 3,
                          cap: TextCapitalization.words,
                          check: _check.contains('address'),
                        ),
                      ],
                    ),
                  ),
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('More from the card', style: AppText.label),
                        Text(
                          'Licence numbers, hours, slogans and anything else worth keeping.',
                          style: AppText.secondary,
                        ),
                        _gap,
                        for (final (i, e) in _extras.indexed) ...[
                          Row(
                            children: [
                              SizedBox(width: 110, child: _field('Label', e.label, cap: TextCapitalization.words)),
                              const SizedBox(width: 10),
                              Expanded(child: _field('Text', e.value)),
                              IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () => setState(() => _extras.removeAt(i).dispose()),
                              ),
                            ],
                          ),
                          _gap,
                        ],
                        _addButton('Add a line', () => setState(() => _extras.add(_ExtraRow('', '')))),
                      ],
                    ),
                  ),
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (leads) ...[
                          Text('Lead rating', style: AppText.label),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final r in LeadRating.values)
                                ChoiceChip(
                                  label: Text(ratingLabel(r)),
                                  selected: _rating == r,
                                  showCheckmark: false,
                                  onSelected: (on) => setState(() => _rating = on ? r : null),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                        Text('Follow up', style: AppText.label),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _followup == null ? 'Not set' : DateFormat('EEE, MMM d, y').format(_followup!),
                                style: AppText.body,
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  initialDate: _followup ?? DateTime.now().add(const Duration(days: 7)),
                                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                                  lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                                );
                                if (d != null) setState(() => _followup = DateTime(d.year, d.month, d.day, 8));
                              },
                              child: Text(_followup == null ? 'Set date' : 'Change'),
                            ),
                            if (_followup != null)
                              IconButton(
                                tooltip: 'Clear follow-up',
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => setState(() => _followup = null),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _field('Notes', _notes, maxLines: 6, cap: TextCapitalization.sentences),
                        const SizedBox(height: 8),
                        if (!_isPlace)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _trackCareer,
                            activeThumbColor: Tokens.brass,
                            onChanged: (v) => setState(() => _trackCareer = v),
                            title: Text('Track career changes', style: AppText.bodyStrong),
                            subtitle: Text(
                              'Suggest an update when a new card shows a new company.',
                              style: AppText.secondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Container(
              decoration: BoxDecoration(
                color: Tokens.surface,
                border: Border(top: BorderSide(color: Tokens.hairline)),
              ),
              padding: const EdgeInsets.fromLTRB(Tokens.gutter, 12, Tokens.gutter, 12),
              child: Row(
                children: [
                  Expanded(
                    child: widget.scan == null
                        ? OutlinedButton(onPressed: _maybeLeave, child: const Text('Cancel'))
                        : OutlinedButton(onPressed: _saving ? null : _save, child: const Text('Save')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _saving ? null : (widget.scan == null ? _save : () => _save(next: true)),
                      child: _saving
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Tokens.onAction),
                            )
                          : Text(widget.scan == null ? 'Save' : 'Save and review next'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _gap = SizedBox(height: 12);

  Widget _addButton(String label, VoidCallback onTap) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextButton.icon(onPressed: onTap, icon: const Icon(Icons.add, size: 18), label: Text(label)),
    ),
  );

  Widget _field(
    String label,
    TextEditingController c, {
    TextInputType? keyboard,
    int maxLines = 1,
    TextCapitalization cap = TextCapitalization.none,
    bool autofocus = false,
    bool check = false,
    String? Function(String?)? validator,
  }) => TextFormField(
    controller: c,
    autofocus: autofocus,
    keyboardType: maxLines > 1 ? TextInputType.multiline : keyboard,
    textCapitalization: cap,
    minLines: 1,
    maxLines: maxLines,
    validator: validator,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    decoration: _checkDecoration(label, check),
  );
}

/// Amber outline and "check" note on fields the parser was unsure about.
InputDecoration _checkDecoration(String label, bool check) => check
    ? InputDecoration(
        labelText: label,
        helperText: 'Check this against the card',
        helperStyle: AppText.secondary.copyWith(color: Tokens.amberFg, fontSize: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusSm),
          borderSide: BorderSide(color: Tokens.amberFg, width: 1.4),
        ),
      )
    : InputDecoration(labelText: label);

class _PhoneField extends StatefulWidget {
  final _PhoneRow row;
  final String region;
  final ValueChanged<String> onLabel;
  final VoidCallback? onRemove;
  const _PhoneField({required this.row, required this.region, required this.onLabel, this.onRemove});

  @override
  State<_PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<_PhoneField> {
  @override
  Widget build(BuildContext context) {
    final raw = widget.row.ctl.text.trim();
    final normalized = raw.isEmpty ? '' : normalizePhone(raw, widget.region);
    final valid = normalized.startsWith('+');
    // The number gets the whole width so it is always readable; type and
    // extension sit on the line under it (phone test F20).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: widget.row.ctl,
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: widget.row.label == 'Fax' ? 'Fax number' : 'Phone number',
                  helperText: raw.isEmpty
                      ? null
                      : valid
                      ? 'Saved as ${formatPhone(normalized)}'
                      : 'Not a valid number for ${widget.region}. It will be saved as typed.',
                  helperMaxLines: 2,
                  helperStyle: AppText.secondary.copyWith(fontSize: 12, color: valid ? Tokens.ink2 : Tokens.amberFg),
                ),
              ),
            ),
            if (widget.onRemove != null)
              IconButton(
                tooltip: 'Remove phone',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: widget.onRemove,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: widget.row.label,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [for (final l in phoneLabels) DropdownMenuItem(value: l, child: Text(l))],
                onChanged: (v) => v == null ? null : widget.onLabel(v),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 104,
              child: TextFormField(
                controller: widget.row.ext,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Ext.'),
              ),
            ),
            if (widget.onRemove != null) const SizedBox(width: 48),
          ],
        ),
      ],
    );
  }
}

/// Text field with suggestions from existing contacts (one company, one spelling).
class _AutoField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final Future<List<String>> Function(String) suggest;
  final bool check;
  const _AutoField({required this.label, required this.controller, required this.suggest, this.check = false});

  @override
  State<_AutoField> createState() => _AutoFieldState();
}

class _AutoFieldState extends State<_AutoField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<String>(
    textEditingController: widget.controller,
    focusNode: _focus,
    optionsBuilder: (v) async {
      final q = v.text.trim();
      if (q.length < 2) return const <String>[];
      final all = await widget.suggest(q);
      return all.where((s) => s.toLowerCase() != q.toLowerCase());
    },
    fieldViewBuilder: (context, ctl, focus, onSubmit) => TextFormField(
      controller: ctl,
      focusNode: focus,
      textCapitalization: TextCapitalization.words,
      decoration: _checkDecoration(widget.label, widget.check),
    ),
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusSm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240, maxWidth: 320),
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [for (final o in options) ListTile(dense: true, title: Text(o), onTap: () => onSelected(o))],
          ),
        ),
      ),
    ),
  );
}
