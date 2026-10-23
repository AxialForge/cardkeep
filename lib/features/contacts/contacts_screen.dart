import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/drawer.dart';
import '../../app/plural.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/contacts/contact_models.dart';
import '../../core/db/tables.dart';
import '../../core/tags/tags_repository.dart';
import '../../core/vcard/vcard.dart';
import '../tags/tags_screen.dart';

/// Contacts list (mockup Main.dc.html).
class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});
  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _selected = <String>{};
  final _headerKeys = <String, GlobalKey>{};
  Timer? _debounce;
  List<String> _indexLetters = const [];
  final _scaffold = GlobalKey<ScaffoldState>();
  final _stackKey = GlobalKey();
  final _chipsKey = GlobalKey();
  bool _drawerOpen = false;

  /// Top of the A-Z strip, measured after layout; null until the chips are laid out.
  double? _indexTopY;

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(contactFilterProvider).query;
    _scroll.addListener(_measureIndex);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 150),
      () => ref.read(contactFilterProvider.notifier).update((f) => f.copyWith(query: q)),
    );
  }

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  Future<void> _rateSelected(LeadRating? r) async {
    final repo = ref.read(contactsRepoProvider);
    for (final id in _selected) {
      await repo.setLeadRating(id, r);
    }
    setState(_selected.clear);
  }

  /// "+" opens the ways to add someone (S10b.9), anchored under the button.
  Future<void> _showAddMenu(BuildContext anchor) async {
    final box = anchor.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(anchor).context.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset(0, box.size.height + 6), ancestor: overlay);
    final choice = await showMenu<String>(
      context: anchor,
      position: RelativeRect.fromLTRB(at.dx - 200, at.dy, overlay.size.width - at.dx - box.size.width, 0),
      items: const [
        PopupMenuItem(
          value: '/scan',
          child: ListTile(leading: Icon(Icons.photo_camera_outlined), title: Text('Scan a card')),
        ),
        PopupMenuItem(
          value: '/scan?mode=batch',
          child: ListTile(
            leading: Icon(Icons.burst_mode_outlined),
            title: Text('Scan many cards'),
            subtitle: Text('Batch: one card after another'),
          ),
        ),
        PopupMenuItem(
          value: '/scan?mode=pile',
          child: ListTile(
            leading: Icon(Icons.dashboard_outlined),
            title: Text('Scan a pile'),
            subtitle: Text('Several cards in one photo'),
          ),
        ),
        PopupMenuItem(
          value: '/tap',
          child: ListTile(leading: Icon(Icons.contactless_outlined), title: Text('Tap an NFC card')),
        ),
        PopupMenuItem(
          value: '/contact/new',
          child: ListTile(leading: Icon(Icons.person_add_alt_1_outlined), title: Text('Add by hand')),
        ),
        PopupMenuItem(
          value: '/scan?pick=1',
          child: ListTile(
            leading: Icon(Icons.photo_library_outlined),
            title: Text('Import card photos'),
            subtitle: Text('From your gallery'),
          ),
        ),
      ],
    );
    if (choice != null && mounted) unawaited(context.push(choice));
  }

  Future<void> _tagSelected() async {
    final picked = await pickTags(context, initial: const {}, title: 'Add tags to ${_selected.length}');
    if (picked == null || picked.isEmpty) return;
    final ids = _selected.toList();
    for (final t in picked) {
      await ref.read(tagsRepoProvider).addToAll(ids, t);
    }
    setState(_selected.clear);
    if (mounted) showMessage(context, 'Tagged ${ids.length} contact${ids.length == 1 ? '' : 's'}');
  }

  Future<void> _shareSelected() async {
    final repo = ref.read(contactsRepoProvider);
    final cards = <ExportContact>[];
    for (final id in _selected) {
      final d = await repo.loadDetail(id);
      if (d != null) cards.add(repo.toExport(d));
    }
    if (cards.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(writeVCards(cards))),
            mimeType: 'text/vcard',
            name: 'contacts.vcf',
          ),
        ],
        fileNameOverrides: ['contacts.vcf'],
      ),
    );
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    final ok = await confirm(
      context,
      title: 'Delete ${ids.length} contact${ids.length == 1 ? '' : 's'}?',
      message: 'You can undo this for a few seconds.',
      action: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final repo = ref.read(contactsRepoProvider);
    for (final id in ids) {
      await repo.delete(id);
    }
    setState(_selected.clear);
    if (!mounted) return;
    showMessage(
      context,
      'Deleted ${plural(ids.length, 'contact')}',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          for (final id in ids) {
            await repo.restore(id);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(contactFilterProvider);
    final contacts = ref.watch(contactsProvider);
    final stats = ref.watch(statsProvider).value;
    final bigText = MediaQuery.textScalerOf(context).scale(10) > 13;
    if (bigText) _indexLetters = const [];
    // Re-measured after every layout: the banner, results and font size move the chips.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureIndex();
    });
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Tokens.groundOverlay,
      child: PopScope(
        // Back closes the drawer or the selection first. go_router's root pop
        // otherwise exits the app with the drawer still open (seen on Android 17).
        canPop: !_selecting && !_drawerOpen,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_drawerOpen) {
            _scaffold.currentState?.closeDrawer();
          } else {
            setState(_selected.clear);
          }
        },
        child: Scaffold(
          key: _scaffold,
          drawer: const AppDrawer(current: '/'),
          onDrawerChanged: (open) => setState(() => _drawerOpen = open),
          // Hidden while typing: over the keyboard it covers the search results (phone test F2).
          floatingActionButton: _selecting || MediaQuery.viewInsetsOf(context).bottom > 0
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => context.push('/scan'),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Scan card'),
                ),
          bottomNavigationBar: _selecting ? _selectionBar() : null,
          body: SafeArea(
            bottom: false,
            child: Stack(
              key: _stackKey,
              children: [
                CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
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
                            Builder(
                              builder: (c) =>
                                  DiscButton(icon: Icons.add, tooltip: 'Add contact', onPressed: () => _showAddMenu(c)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_selecting ? '${_selected.length} selected' : 'Contacts', style: AppText.display),
                            const SizedBox(height: 4),
                            Text(
                              '${plural(stats?.people ?? 0, 'person', 'people')} across ${plural(stats?.companies ?? 0, 'company', 'companies')}'
                              '${(stats?.places ?? 0) > 0 ? ' · ${plural(stats!.places, 'place')}' : ''}',
                              style: AppText.secondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if ((stats?.followupsThisWeek ?? 0) > 0)
                      SliverToBoxAdapter(child: _FollowupBanner(count: stats!.followupsThisWeek)),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(Tokens.gutter, 10, Tokens.gutter, 8),
                        child: TextField(
                          controller: _search,
                          onChanged: _onSearch,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Search names, companies, phones, notes',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: filter.query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    icon: const Icon(Icons.close),
                                    onPressed: () {
                                      _search.clear();
                                      _onSearch('');
                                    },
                                  ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(Tokens.radius),
                              borderSide: BorderSide(color: Tokens.hairline),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(Tokens.radius),
                              borderSide: BorderSide(color: Tokens.hairline),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: KeyedSubtree(
                        key: _chipsKey,
                        child: _SortAndFilters(filter: filter),
                      ),
                    ),
                    ...contacts.when(
                      loading: () => [const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))],
                      error: (e, _) => [SliverFillRemaining(child: Center(child: Text('Could not load contacts: $e')))],
                      data: (rows) => rows.isEmpty
                          ? [SliverFillRemaining(hasScrollBody: false, child: _empty(filter))]
                          : _list(rows, filter),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 96)),
                  ],
                ),
                if (_indexLetters.isNotEmpty && !bigText && _indexTopY != null)
                  // Beside the list body only: starts below the filter chips wherever
                  // they are scrolled to, measured after layout (phone test F29).
                  Positioned(
                    right: 0,
                    top: _indexTopY,
                    bottom: 96,
                    child: _IndexStrip(letters: _indexLetters, onLetter: _jumpTo),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty(ContactFilter f) => f.query.isNotEmpty || f.hasFilters
      ? const EmptyState(
          icon: Icons.search_off,
          title: 'No matches',
          message: 'Try a shorter search or clear the filters.',
        )
      : EmptyState(
          icon: Icons.contacts_outlined,
          title: 'No contacts yet',
          message: 'Scan a business card, or add someone by hand.',
          action: Column(
            children: [
              FilledButton.icon(
                onPressed: () => context.push('/scan'),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Scan a card'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => context.push('/contact/new'),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Add by hand'),
              ),
            ],
          ),
        );

  String _section(ContactSummary c, ContactSort sort) {
    switch (sort) {
      case ContactSort.name:
        final byFirst = ref.read(sortByFirstProvider).value ?? false;
        final name = byFirst ? c.first : c.last;
        final key = (name.isNotEmpty ? name : c.displayName).trim();
        if (key.isEmpty) return '#';
        final ch = key[0].toUpperCase();
        return RegExp(r'[A-Z]').hasMatch(ch) ? ch : '#';
      case ContactSort.company:
        return (c.company == null || c.company!.isEmpty) ? 'No company' : c.company!;
      case ContactSort.recent:
        final days = DateTime.now().difference(c.createdAt).inDays;
        return days < 1
            ? 'Today'
            : days < 7
            ? 'This week'
            : days < 31
            ? 'This month'
            : 'Earlier';
    }
  }

  List<Widget> _list(List<ContactSummary> rows, ContactFilter f) {
    final groups = <String, List<ContactSummary>>{};
    for (final r in rows) {
      groups.putIfAbsent(_section(r, f.sort), () => []).add(r);
    }
    _headerKeys.removeWhere((k, _) => !groups.containsKey(k));
    final showIndex = f.sort == ContactSort.name && f.query.isEmpty && rows.length > 20;
    _indexLetters = showIndex ? groups.keys.toList() : const [];
    // Companies whose name matches the search open their page (S14d.3).
    final q = f.query.trim().toLowerCase();
    final companies = <String, String>{
      if (q.isNotEmpty)
        for (final r in rows)
          if (r.companyId != null && !r.isPlace && (r.company ?? '').toLowerCase().contains(q))
            r.companyId!: r.company!,
    };
    return [
      if (companies.isNotEmpty)
        SliverToBoxAdapter(
          child: Panel(
            padding: const EdgeInsets.fromLTRB(6, 12, 6, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(padding: EdgeInsets.fromLTRB(10, 0, 10, 4), child: Overline('Companies')),
                for (final MapEntry(key: id, value: name) in companies.entries)
                  ListTile(
                    leading: Icon(Icons.domain, color: Tokens.ink),
                    title: Text(name, style: AppText.bodyStrong),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/company/$id'),
                  ),
              ],
            ),
          ),
        ),
      SliverPadding(
        padding: EdgeInsets.only(right: showIndex ? 18 : 0),
        sliver: SliverList.list(
          children: [
            for (final g in groups.entries)
              Panel(
                key: _headerKeys.putIfAbsent(g.key, GlobalKey.new),
                padding: const EdgeInsets.fromLTRB(6, 12, 6, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // In the Company view the header opens the company page (S14d.3).
                    if (f.sort == ContactSort.company && g.value.first.companyId != null && !g.value.first.isPlace)
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => context.push('/company/${g.value.first.companyId}'),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 2, 6, 6),
                          child: Row(
                            children: [
                              Expanded(child: Overline(g.key)),
                              Text('Company page', style: AppText.label.copyWith(color: Tokens.brassText)),
                              Icon(Icons.chevron_right, size: 18, color: Tokens.brassText),
                            ],
                          ),
                        ),
                      )
                    else
                      Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 4), child: Overline(g.key)),
                    for (final (i, c) in g.value.indexed) ...[
                      if (i > 0) const Divider(indent: 70, endIndent: 10),
                      _ContactRow(
                        contact: c,
                        selected: _selected.contains(c.id),
                        onTap: () => _selecting ? _toggle(c.id) : context.push('/contact/${c.id}'),
                        onLongPress: () => _toggle(c.id),
                        showRating: ref.watch(leadsEnabledProvider).value ?? true,
                        logo: c.logo == null ? null : ref.watch(imageStoreProvider).value?.logo(c.logo!),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  /// Measures the bottom of the filter chips after layout and moves the A-Z strip
  /// there. Before the chips are laid out the strip is not shown at all, so it can
  /// never start beside the banner or search box.
  void _measureIndex() {
    final chips = _chipsKey.currentContext?.findRenderObject() as RenderBox?;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (chips == null || stack == null || !chips.attached || !stack.hasSize) return;
    final bottom = chips.localToGlobal(Offset(0, chips.size.height), ancestor: stack).dy;
    final y = bottom < 8 ? 8.0 : bottom;
    if (_indexTopY == null || (y - _indexTopY!).abs() > 0.5) setState(() => _indexTopY = y);
  }

  /// Sections far off screen are not built yet, so a tap on their letter first
  /// scrolls to an estimate, then aligns on the header once it exists (phone test F26).
  void _jumpTo(String letter) {
    final ctx = _headerKeys[letter]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 150));
      return;
    }
    final i = _indexLetters.indexOf(letter);
    if (i < 0 || !_scroll.hasClients) return;
    final pos = _scroll.position;
    _scroll.jumpTo(pos.maxScrollExtent * i / _indexLetters.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _headerKeys[letter]?.currentContext;
      if (c != null) Scrollable.ensureVisible(c);
    });
  }

  Widget _selectionBar() => BottomAppBar(
    color: Tokens.surface,
    child: Row(
      children: [
        IconButton(tooltip: 'Cancel', icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
        const Spacer(),
        if (ref.watch(leadsEnabledProvider).value ?? true)
          PopupMenuButton<LeadRating?>(
            tooltip: 'Set lead rating',
            icon: const Icon(Icons.local_fire_department_outlined),
            onSelected: _rateSelected,
            itemBuilder: (_) => [
              for (final r in LeadRating.values) PopupMenuItem(value: r, child: Text(ratingLabel(r))),
              const PopupMenuItem(value: null, child: Text('No rating')),
            ],
          ),
        IconButton(tooltip: 'Add a tag', icon: const Icon(Icons.sell_outlined), onPressed: _tagSelected),
        IconButton(tooltip: 'Share as vCard', icon: const Icon(Icons.ios_share), onPressed: _shareSelected),
        IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _deleteSelected),
      ],
    ),
  );
}

class _FollowupBanner extends ConsumerWidget {
  final int count;
  const _FollowupBanner({required this.count});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(Tokens.gutter, 12, Tokens.gutter, 0),
    child: Material(
      color: Tokens.strong,
      borderRadius: BorderRadius.circular(Tokens.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(Tokens.radius),
        onTap: () => context.push('/followups'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: Tokens.onStrong.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(Icons.schedule, color: Tokens.brass, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$count follow-up${count == 1 ? '' : 's'} due this week',
                  style: AppText.bodyStrong.copyWith(color: Tokens.onStrong),
                ),
              ),
              Icon(Icons.chevron_right, color: Tokens.onStrong),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SortAndFilters extends ConsumerWidget {
  final ContactFilter filter;
  const _SortAndFilters({required this.filter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(contactFilterProvider.notifier);
    Widget chip(String label, bool on, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(label: Text(label), selected: on, onSelected: (_) => onTap(), showCheckmark: false),
    );
    final byFirst = ref.watch(sortByFirstProvider).value ?? false;
    final leads = ref.watch(leadsEnabledProvider).value ?? true;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.gutter),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<ContactSort>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                backgroundColor: Tokens.selected,
                selectedBackgroundColor: Tokens.surface,
                selectedForegroundColor: Tokens.brassText,
                side: BorderSide(color: Tokens.hairline),
              ),
              segments: const [
                ButtonSegment(value: ContactSort.name, label: Text('Name')),
                ButtonSegment(value: ContactSort.company, label: Text('Company')),
                ButtonSegment(value: ContactSort.recent, label: Text('Recent')),
              ],
              selected: {filter.sort},
              onSelectionChanged: (s) => n.update((f) => f.copyWith(sort: s.single)),
            ),
          ),
        ),
        if (filter.sort == ContactSort.name)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () => ref.read(settingsRepoProvider).setSortByFirst(!byFirst),
                icon: const Icon(Icons.swap_vert, size: 18),
                label: Text(byFirst ? 'By first name' : 'By last name'),
              ),
            ),
          ),
        // Sized by its content (not a fixed height) so large text sizes don't clip the chips.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(Tokens.gutter, 8, Tokens.gutter, 4),
          child: Row(
            children: [
              for (final t in ref.watch(tagsProvider).value ?? const <TagView>[])
                if (t.count > 0 || filter.tagId == t.id)
                  chip(
                    t.name,
                    filter.tagId == t.id,
                    () => n.update((f) => f.copyWith(tagId: () => f.tagId == t.id ? null : t.id)),
                  ),
              for (final r in leads ? LeadRating.values : const <LeadRating>[])
                chip(
                  ratingLabel(r),
                  filter.rating == r,
                  () => n.update((f) => f.copyWith(rating: () => f.rating == r ? null : r)),
                ),
              chip('Places', filter.placesOnly, () => n.update((f) => f.copyWith(placesOnly: !f.placesOnly))),
              chip(
                'Follow-up due',
                filter.followupOnly,
                () => n.update((f) => f.copyWith(followupOnly: !f.followupOnly)),
              ),
              chip(
                'Moved',
                filter.status == PersonStatus.moved,
                () => n.update(
                  (f) => f.copyWith(status: () => f.status == PersonStatus.moved ? null : PersonStatus.moved),
                ),
              ),
              chip(
                'Retired',
                filter.status == PersonStatus.retired,
                () => n.update(
                  (f) => f.copyWith(status: () => f.status == PersonStatus.retired ? null : PersonStatus.retired),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  final ContactSummary contact;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool showRating;
  final File? logo;
  const _ContactRow({
    this.logo,
    required this.contact,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    this.showRating = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = contact;
    final status = Pill.status(c.status);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(color: selected ? Tokens.selected : null, borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            selected
                ? CircleAvatar(
                    radius: 22,
                    backgroundColor: Tokens.action,
                    child: Icon(Icons.check, color: Tokens.onAction),
                  )
                : Avatar(c.initials, image: logo, place: c.isPlace),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.displayName.isEmpty ? '(No name)' : c.displayName,
                    style: AppText.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (c.subtitle.isNotEmpty)
                    Text(c.subtitle, style: AppText.secondary, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (status != null) ...[const SizedBox(width: 6), status],
            if (showRating && c.leadRating != null) ...[const SizedBox(width: 6), Pill.rating(c.leadRating!)],
          ],
        ),
      ),
    );
  }
}

/// A–Z strip on the right edge for long name-sorted lists. Drag or tap to jump.
class _IndexStrip extends StatelessWidget {
  final List<String> letters;
  final void Function(String) onLetter;
  const _IndexStrip({required this.letters, required this.onLetter});

  void _hit(BuildContext context, Offset local) {
    final box = context.findRenderObject()! as RenderBox;
    final i = (local.dy / box.size.height * letters.length).floor().clamp(0, letters.length - 1);
    onLetter(letters[i]);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Alphabet index',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _hit(context, d.localPosition),
      onVerticalDragUpdate: (d) => _hit(context, d.localPosition),
      // Letters fill the strip evenly, so the touch position maps onto the letter
      // under the finger (a centred cluster mapped taps to the wrong letter).
      child: SizedBox(
        width: 22,
        child: Column(
          children: [
            for (final l in letters)
              Expanded(
                child: Center(
                  child: Text(l, style: AppText.label.copyWith(fontSize: 11, color: Tokens.brassText)),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
