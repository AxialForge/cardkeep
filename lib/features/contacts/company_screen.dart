import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/plural.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/contacts/company_repository.dart';
import '../../core/contacts/contact_models.dart';
import '../../core/contacts/contacts_repository.dart';
import '../../core/images/image_store.dart';
import '../../core/vcard/vcard.dart';

final companyRepoProvider = Provider((ref) => CompanyRepository(ref.watch(databaseProvider)));

final companyProvider = StreamProvider.autoDispose.family<CompanyOverview?, String>(
  (ref, id) => ref.watch(companyRepoProvider).watch(id),
);

/// Company page (S14d.2): everyone you know there, their places, where you met
/// them, and what the company shares.
class CompanyScreen extends ConsumerWidget {
  final String id;
  const CompanyScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(placeCategoriesProvider); // category labels follow renames
    final data = ref.watch(companyProvider(id));
    final store = ref.watch(imageStoreProvider).value;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Tokens.groundOverlay,
      child: Scaffold(
        body: SafeArea(
          child: switch (data) {
            AsyncData(value: null) => const EmptyState(
              icon: Icons.domain_disabled_outlined,
              title: 'Company not found',
              message: 'It may have been merged or removed.',
            ),
            AsyncData(value: final c?) => ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Tokens.gutter, 8, Tokens.gutter, 0),
                  child: Row(
                    children: [
                      DiscButton(icon: Icons.arrow_back, tooltip: 'Back', onPressed: () => context.pop()),
                      const Spacer(),
                      DiscButton(
                        icon: Icons.ios_share,
                        tooltip: 'Share all as vCard',
                        onPressed: c.everyone.isEmpty ? null : () => _shareAll(ref, c),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: Row(
                    children: [
                      Avatar(_initials(c.name), size: 64, image: c.logo == null ? null : store?.logo(c.logo!)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.name, style: AppText.title),
                            Text(_summary(c), style: AppText.secondary),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (c.website != null || c.address != null || c.sharedPhones.isNotEmpty)
                  Panel(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (final p in c.sharedPhones)
                          ListTile(
                            leading: Icon(Icons.call_outlined, color: Tokens.ink),
                            title: Text(formatPhone(p), style: AppText.body),
                            subtitle: Text('Shared by the company', style: AppText.secondary),
                            onTap: () => ref.read(launcherProvider).call(p),
                          ),
                        if (c.website case final w? when w.isNotEmpty)
                          ListTile(
                            leading: Icon(Icons.language, color: Tokens.ink),
                            title: Text(w, style: AppText.body),
                            onTap: () => ref.read(launcherProvider).web(w),
                          ),
                        if (c.address case final a? when a.isNotEmpty)
                          ListTile(
                            leading: Icon(Icons.place_outlined, color: Tokens.ink),
                            title: Text(a, style: AppText.body),
                            onTap: () => ref.read(launcherProvider).map(a),
                          ),
                      ],
                    ),
                  ),
                _PeoplePanel(title: 'People here', people: c.current, store: store),
                _PeoplePanel(title: 'Places', people: c.places, store: store),
                _PeoplePanel(title: 'Used to work here', people: c.former, store: store),
                if (c.events.isNotEmpty)
                  Panel(
                    padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Overline('Met at')),
                        for (final e in c.events)
                          ListTile(
                            dense: true,
                            leading: Icon(Icons.event_outlined, color: Tokens.ink),
                            title: Text(e.name, style: AppText.bodyStrong),
                            subtitle: Text(DateFormat.yMMMd().format(e.start), style: AppText.secondary),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/event/${e.id}'),
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Tokens.gutter, 8, Tokens.gutter, 0),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.person_add_alt),
                    label: Text('Add a person at ${c.name}'),
                    onPressed: () => context.push('/contact/new', extra: ContactDraft(company: c.name)),
                  ),
                ),
              ],
            ),
            AsyncError(:final error) => Center(child: Text('Could not load: $error')),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }

  static String _summary(CompanyOverview c) {
    final parts = [
      if (c.current.isNotEmpty) plural(c.current.length, 'person', 'people'),
      if (c.places.isNotEmpty) plural(c.places.length, 'place'),
      if (c.former.isNotEmpty) '${c.former.length} former',
      if (c.lastContact != null) 'last card ${DateFormat.yMMMd().format(c.lastContact!)}',
    ];
    return parts.join(' · ');
  }

  static String _initials(String name) {
    final w = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (w.isEmpty) return '?';
    return (w.length == 1 ? w.first[0] : '${w.first[0]}${w[1][0]}').toUpperCase();
  }

  Future<void> _shareAll(WidgetRef ref, CompanyOverview c) async {
    final repo = ref.read(contactsRepoProvider);
    final cards = [
      for (final p in c.everyone)
        if (await repo.loadDetail(p.id) case final d?) repo.toExport(d),
    ];
    if (cards.isEmpty) return;
    final name = '${c.name.replaceAll(RegExp(r'[^\w\- ]'), '').trim()}.vcf';
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(Uint8List.fromList(utf8.encode(writeVCards(cards))), mimeType: 'text/vcard', name: name),
        ],
        fileNameOverrides: [name],
      ),
    );
  }
}

class _PeoplePanel extends StatelessWidget {
  final String title;
  final List<ContactSummary> people;
  final ImageStore? store;
  const _PeoplePanel({required this.title, required this.people, required this.store});

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    return Panel(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Overline('$title (${people.length})')),
          for (final p in people)
            ListTile(
              leading: Avatar(
                p.initials,
                size: 36,
                place: p.isPlace,
                image: p.logo == null ? null : store?.logo(p.logo!),
              ),
              title: Text(p.displayName.isEmpty ? '(No name)' : p.displayName, style: AppText.bodyStrong),
              subtitle: p.isPlace
                  ? Text(p.subtitle, style: AppText.secondary)
                  : (p.title == null || p.title!.isEmpty ? null : Text(p.title!, style: AppText.secondary)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/contact/${p.id}'),
            ),
        ],
      ),
    );
  }
}
