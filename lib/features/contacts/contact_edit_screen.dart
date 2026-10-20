import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/contacts/contact_models.dart';
import '../../core/contacts/contacts_repository.dart';
import '../../core/db/tables.dart';
import '../../core/links/link_launcher.dart';
import '../../scan/scan_pipeline.dart';
import '../scan/scan_review.dart';

const phoneLabels = ['Mobile', 'Office', 'Direct', 'Other'];
final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

/// New and edit contact (mockup ContactEdit.dc.html). [id] null = new contact.
class ContactEditScreen extends ConsumerStatefulWidget {
  final String? id;

  /// A scanned card to prefill from (new contacts only).
  final ScanHandoff? scan;
  const ContactEditScreen({super.key, this.id, this.scan});

  @override
  ConsumerState<ContactEditScreen> createState() => _ContactEditScreenState();
}

class _PhoneRow {
  String label;
  final TextEditingController ctl;
  _PhoneRow(this.label, String value) : ctl = TextEditingController(text: value);
}

class _ContactEditScreenState extends ConsumerState<ContactEditScreen> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _title = TextEditingController();
  final _company = TextEditingController();
  final _website = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
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
      _check = uncertainFields(s.front.parsed);
    }
    if (!mounted) return;
    _first.text = draft.first;
    _last.text = draft.last;
    _title.text = draft.title;
    _company.text = draft.company;
    _website.text = draft.website;
    _address.text = draft.address;
    _notes.text = draft.notes;
    for (final p in draft.phones) {
      _phones.add(_PhoneRow(phoneLabels.contains(p.label) ? p.label : 'Other', formatPhone(p.value)));
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
    for (final c in [_first, _last, _title, _company, _website, _address, _notes, ..._emails]) {
      c.dispose();
    }
    for (final p in _phones) {
      p.ctl.dispose();
    }
    super.dispose();
  }

  ContactDraft _draft() => ContactDraft(
    first: _first.text,
    last: _last.text,
    title: _title.text,
    company: _company.text,
    phones: [
      for (final p in _phones)
        if (p.ctl.text.trim().isNotEmpty) LabeledValue(p.label, p.ctl.text.trim()),
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
  );

  bool get _dirty {
    final a = _original, b = _draft();
    if (a == null) return false;
    String sig(ContactDraft d) => [
      d.first,
      d.last,
      d.title,
      d.company,
      d.website,
      d.address,
      d.notes,
      d.leadRating,
      d.followupAt,
      d.trackCareer,
      d.phones.map((p) => '${p.label}:${p.value}').join('|'),
      d.emails.join('|'),
    ].join('\u0000');
    return sig(a) != sig(b);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final d = _draft();
    if (d.isEmpty) {
      showMessage(context, 'Add at least a name, company, phone or email.');
      return;
    }
    setState(() => _saving = true);
    final region = ref.read(regionProvider).value ?? 'US';
    final repo = ref.read(contactsRepoProvider);
    final id = await repo.save(
      d,
      id: widget.id,
      region: region,
      source: widget.scan == null ? RoleSource.manual : RoleSource.scan,
    );
    final scan = widget.scan;
    if (scan != null) {
      await repo.attachCard(id, frontHash: scan.front.hash, backHash: scan.back?.hash, ocrJson: scan.front.ocrJson);
    }
    if (!mounted) return;
    _original = d;
    if (_isNew) {
      context.pushReplacement('/contact/$id');
    } else {
      context.pop();
    }
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
      // A scanned card that isn't saved leaves no images behind.
      final scan = widget.scan;
      if (scan != null) {
        final store = await ref.read(imageStoreProvider.future);
        await store.delete(scan.front.hash);
        if (scan.back != null) await store.delete(scan.back!.hash);
      }
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final region = ref.watch(regionProvider).value ?? 'US';
    final repo = ref.read(contactsRepoProvider);

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
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: DiscButton(icon: Icons.arrow_back, tooltip: 'Back', onPressed: _maybeLeave),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_isNew ? 'New contact' : 'Edit contact', style: AppText.display),
                        if (!_isNew && _original!.displayName.isNotEmpty)
                          Text(_original!.displayName, style: AppText.secondary),
                      ],
                    ),
                  ),
                  if (widget.scan != null) _ScannedCardPanel(scan: widget.scan!, check: _check),
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                        for (final (i, p) in _phones.indexed) ...[
                          _PhoneField(
                            row: p,
                            region: region,
                            onLabel: (l) => setState(() => p.label = l),
                            onRemove: _phones.length == 1
                                ? null
                                : () => setState(() {
                                    _phones.removeAt(i).ctl.dispose();
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
                              onPressed: () => _website.text.trim().isEmpty
                                  ? null
                                  : ref.read(launcherProvider).open(LinkLauncher.webUri(_website.text)),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                    child: OutlinedButton(onPressed: _maybeLeave, child: const Text('Cancel')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Tokens.onAction),
                            )
                          : const Text('Save'),
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

class _ScannedCardPanel extends StatelessWidget {
  final ScanHandoff scan;
  final Set<String> check;
  const _ScannedCardPanel({required this.scan, required this.check});

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final s in [scan.front, ?scan.back])
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(s.thumb, height: 84, fit: BoxFit.contain, semanticLabel: 'Scanned card'),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          scan.front.ocr == null
              ? 'Card saved. Type the details from the photo.'
              : check.isEmpty
              ? 'Read from the card. Check the details, then save.'
              : 'Read from the card. Fields marked amber need a second look.',
          style: AppText.secondary,
        ),
      ],
    ),
  );
}

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 124,
              child: DropdownButtonFormField<String>(
                initialValue: widget.row.label,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Phone'),
                items: [for (final l in phoneLabels) DropdownMenuItem(value: l, child: Text(l))],
                onChanged: (v) => v == null ? null : widget.onLabel(v),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: widget.row.ctl,
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Number'),
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
        if (raw.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 134, top: 4),
            child: Text(
              valid
                  ? 'Saved as ${formatPhone(normalized)}'
                  : 'Not a valid number for ${widget.region}. It will be saved as typed.',
              style: AppText.secondary.copyWith(fontSize: 12, color: valid ? Tokens.ink2 : Tokens.amberFg),
            ),
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
