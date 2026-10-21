import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/contacts/contact_models.dart';
import '../../core/contacts/contacts_repository.dart';
import '../../core/db/database.dart';
import '../../core/dupes/duplicates_repository.dart';
import 'duplicates_screen.dart';

/// Merges done this session, by the kept person's id, so each can be undone
/// until the app closes (S8.7).
class MergeUndoNotifier extends Notifier<Map<String, (MergeUndo, String)>> {
  @override
  Map<String, (MergeUndo, String)> build() => const {};
  void add(MergeUndo u, String loserName) => state = {...state, u.keeperId: (u, loserName)};
  void remove(String keeperId) => state = {...state}..remove(keeperId);
}

final mergeUndoProvider = NotifierProvider<MergeUndoNotifier, Map<String, (MergeUndo, String)>>(MergeUndoNotifier.new);

/// Undo a merge from this session; returns the restored person's id.
Future<void> undoMerge(WidgetRef ref, String keeperId) async {
  final entry = ref.read(mergeUndoProvider)[keeperId];
  if (entry == null) return;
  await ref.read(duplicatesRepoProvider).undo(entry.$1);
  ref.read(mergeUndoProvider.notifier).remove(keeperId);
  ref.invalidate(duplicatePairsProvider);
  ref.invalidate(matchesForProvider);
}

/// Merge (mockup Merge): the two records side by side; pick each field, the
/// rest (phones, emails, cards, tags, notes) is combined (S8.4).
class MergeScreen extends ConsumerStatefulWidget {
  final String a, b;
  const MergeScreen({super.key, required this.a, required this.b});

  @override
  ConsumerState<MergeScreen> createState() => _MergeScreenState();
}

class _MergeScreenState extends ConsumerState<MergeScreen> {
  late String _keep = widget.a;
  Side _name = Side.keep, _role = Side.keep, _rating = Side.keep, _followup = Side.keep;
  bool _busy = false;

  String get _lose => _keep == widget.a ? widget.b : widget.a;

  Future<void> _merge(ContactDetail keep, ContactDetail lose) async {
    setState(() => _busy = true);
    final undo = await ref
        .read(duplicatesRepoProvider)
        .merge(_keep, _lose, MergeChoices(name: _name, role: _role, rating: _rating, followup: _followup));
    ref.read(mergeUndoProvider.notifier).add(undo, lose.person.displayName);
    ref.invalidate(duplicatePairsProvider);
    ref.invalidate(matchesForProvider);
    if (!mounted) return;
    final keeperId = _keep;
    context.pushReplacement('/contact/$keeperId');
    showMessage(
      context,
      'Merged into one contact',
      action: SnackBarAction(label: 'Undo', onPressed: () => undoMerge(ref, keeperId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = ref.watch(contactDetailProvider(widget.a)).value;
    final b = ref.watch(contactDetailProvider(widget.b)).value;
    if (a == null || b == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Merge')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final keep = _keep == widget.a ? a : b, lose = _keep == widget.a ? b : a;

    String role(ContactDetail d) =>
        [d.currentRole?.title, d.currentRole?.company].where((s) => s != null && s.isNotEmpty).join(' · ');
    String date(DateTime? t) => t == null ? '' : DateFormat('MMM d, y').format(t);

    Widget choice(String label, String k, String l, Side value, void Function(Side) set) {
      if (k == l || l.isEmpty) return _Row(label: label, single: k.isEmpty ? '—' : k);
      if (k.isEmpty) return _Row(label: label, single: l);
      return _Row(label: label, keep: k, lose: l, value: value, onChanged: (s) => setState(() => set(s)));
    }

    final points = <String>{
      for (final d in [keep, lose])
        for (final p in d.points.where((p) => p.isActive))
          p.kind == ContactKind.mobile || p.kind == ContactKind.office ? formatPhone(p.value) : p.value,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Merge contacts')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.gutter, 8, Tokens.gutter, 12),
          child: FilledButton.icon(
            onPressed: _busy ? null : () => _merge(keep, lose),
            icon: const Icon(Icons.merge),
            label: const Text('Merge into one'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Overline('Keep the record of'),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: widget.a,
                      label: Text(a.person.displayName, overflow: TextOverflow.ellipsis),
                    ),
                    ButtonSegment(
                      value: widget.b,
                      label: Text(b.person.displayName, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  selected: {_keep},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() {
                    _keep = s.single;
                    _name = _role = _rating = _followup = Side.keep;
                  }),
                ),
                const SizedBox(height: 6),
                Text(
                  'The other record is removed after its details are moved here. You can undo the merge until you '
                  'close CardKeep.',
                  style: AppText.secondary.copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Overline('Choose for each'),
                choice('Name', keep.person.displayName, lose.person.displayName, _name, (s) => _name = s),
                choice('Title and company', role(keep), role(lose), _role, (s) => _role = s),
                choice(
                  'Lead rating',
                  keep.person.leadRating == null ? '' : ratingLabel(keep.person.leadRating!),
                  lose.person.leadRating == null ? '' : ratingLabel(lose.person.leadRating!),
                  _rating,
                  (s) => _rating = s,
                ),
                choice(
                  'Follow-up',
                  date(keep.person.followupAt),
                  date(lose.person.followupAt),
                  _followup,
                  (s) => _followup = s,
                ),
              ],
            ),
          ),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Overline('Combined'),
                const SizedBox(height: 6),
                for (final p in points)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(p, style: AppText.body),
                  ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (keep.cards.length + lose.cards.length case final n when n > 0)
                      '$n card image${n == 1 ? '' : 's'}',
                    if (keep.person.notes.isNotEmpty || lose.person.notes.isNotEmpty) 'notes from both',
                    'tags from both',
                  ].join(' · '),
                  style: AppText.secondary,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton(
              onPressed: () async {
                await ref.read(duplicatesRepoProvider).dismiss(widget.a, widget.b);
                ref.invalidate(duplicatePairsProvider);
                ref.invalidate(matchesForProvider);
                if (context.mounted) {
                  context.pop();
                  showMessage(context, "Marked as different people. They won't be suggested again.");
                }
              },
              child: const Text('These are different people'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String? single, keep, lose;
  final Side? value;
  final void Function(Side)? onChanged;
  const _Row({required this.label, this.single, this.keep, this.lose, this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget option(Side s, String text) => RadioListTile<Side>(
      value: s,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(text, style: AppText.body),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.label),
          if (single != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(single!, style: AppText.body),
            )
          else
            RadioGroup<Side>(
              groupValue: value,
              onChanged: (s) => onChanged!(s!),
              child: Column(children: [option(Side.keep, keep!), option(Side.lose, lose!)]),
            ),
        ],
      ),
    );
  }
}

/// On a contact's page: "Possible duplicate" cards, and Undo for a merge done
/// this session.
class DuplicateBanner extends ConsumerWidget {
  final String personId;
  const DuplicateBanner({super.key, required this.personId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final undo = ref.watch(mergeUndoProvider)[personId];
    final matches = ref.watch(matchesForProvider(personId)).value ?? const [];
    return Column(
      children: [
        if (undo != null)
          Panel(
            child: Row(
              children: [
                Icon(Icons.merge, color: Tokens.ink2),
                const SizedBox(width: 10),
                Expanded(child: Text('Merged with ${undo.$2}', style: AppText.body)),
                TextButton(onPressed: () => undoMerge(ref, personId), child: const Text('Undo merge')),
              ],
            ),
          ),
        for (final m in matches.take(2)) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Align(alignment: Alignment.centerLeft, child: Overline('Possible duplicate')),
          ),
          DuplicatePairTile(pair: m),
        ],
      ],
    );
  }
}
