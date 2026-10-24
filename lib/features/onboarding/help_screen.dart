import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/drawer.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import 'content/content_model.dart';
import 'content/help_content.dart';
import 'onboarding_pages.dart';
import 'onboarding_providers.dart';

/// Where "Report an issue" opens.
const issuesUrl = 'https://github.com/AxialForge/cardkeep/issues';

/// Help & tips (S15a.7): search, the lessons and answers, replay the tour.
class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    await ref.read(settingsRepoProvider).resetTips();
    if (mounted) showMessage(context, 'Tips will show again the next time you open each screen');
  }

  Future<void> _removeDemo() async {
    final ok = await confirm(
      context,
      title: 'Remove demo data?',
      message: 'The sample contacts tagged Demo are deleted. Your own contacts are not touched.',
      action: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final n = await ref.read(demoDataProvider).remove();
    if (mounted) showMessage(context, 'Removed $n demo contacts');
  }

  Future<void> _about() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    showAboutDialog(
      context: context,
      applicationName: 'CardKeep',
      applicationVersion: '${info.version} (${info.buildNumber})',
      children: [
        Text(
          'Scan business cards, keep contacts, follow up. No account, no cloud, no analytics. Everything stays on this phone.',
          style: AppText.body,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = searchArticles(helpArticles, _query);
    final searching = _query.trim().isNotEmpty;
    final demo = ref.watch(demoCountProvider).value ?? 0;
    return Scaffold(
      drawer: const AppDrawer(current: '/help'),
      appBar: AppBar(title: const Text('Help & tips')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Tokens.gutter, 8, Tokens.gutter, 8),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search help',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Tokens.radius),
                  borderSide: BorderSide(color: Tokens.hairline),
                ),
              ),
            ),
          ),
          if (!searching) ...[
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.play_circle_outline),
                    title: Text('Replay the tour', style: AppText.body),
                    subtitle: Text('Permissions, set-up and the eight lessons', style: AppText.secondary),
                    onTap: () => context.push('/welcome?replay=1'),
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.lightbulb_outline),
                    title: Text('Reset tips', style: AppText.body),
                    subtitle: Text('Show the first-visit tips again', style: AppText.secondary),
                    onTap: _reset,
                  ),
                  if (demo > 0) ...[
                    const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.delete_sweep_outlined),
                      title: Text('Remove demo data', style: AppText.body),
                      subtitle: Text('$demo sample contacts tagged Demo', style: AppText.secondary),
                      onTap: _removeDemo,
                    ),
                  ],
                ],
              ),
            ),
            for (final g in HelpGroup.values.where((g) => helpArticles.any((a) => a.group == g))) ...[
              Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 6), child: Overline(g.label)),
              Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, a) in helpArticles.where((a) => a.group == g).indexed) ...[
                      if (i > 0) const Divider(indent: 16, endIndent: 16, height: 1),
                      _ArticleTile(a),
                    ],
                  ],
                ),
              ),
            ],
            const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 6), child: Overline('CardKeep')),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: Text('Report an issue', style: AppText.body),
                    subtitle: Text('Opens CardKeep\'s issues page on GitHub in your browser', style: AppText.secondary),
                    onTap: () => ref.read(launcherProvider).web(issuesUrl),
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text('About CardKeep', style: AppText.body),
                    subtitle: Text('Version and privacy in a line', style: AppText.secondary),
                    onTap: _about,
                  ),
                ],
              ),
            ),
          ] else if (results.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: EmptyState(
                icon: Icons.search_off,
                title: 'Nothing found',
                message: 'Try fewer words, such as "backup" or "blurry".',
                action: TextButton(
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                  child: const Text('Clear search'),
                ),
              ),
            )
          else
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, a) in results.indexed) ...[
                    if (i > 0) const Divider(indent: 16, endIndent: 16, height: 1),
                    _ArticleTile(a),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ArticleTile extends StatelessWidget {
  final HelpArticle article;
  const _ArticleTile(this.article);

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(article.title, style: AppText.body),
    subtitle: Text(article.summary, style: AppText.secondary),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => context.push('/help/${article.id}'),
  );
}

/// One article: the lesson or answer in full, with Try it when there is a screen.
class HelpArticleScreen extends ConsumerWidget {
  final String id;
  const HelpArticleScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = helpArticles.where((x) => x.id == id).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(a?.group.label ?? 'Help')),
      body: a == null
          ? const EmptyState(icon: Icons.help_outline, title: 'Not found', message: 'That help page does not exist.')
          : TourPage(
              art: a.art,
              title: a.title,
              lead: a.summary,
              children: [
                for (var i = 0; i < a.steps.length; i++) StepTile(i + 1, a.steps[i]),
                if (a.tip != null) ...[TipBox(a.tip!), const SizedBox(height: 14)],
                if (a.tryRoute != null) TryItButton(a),
              ],
            ),
    );
  }
}
