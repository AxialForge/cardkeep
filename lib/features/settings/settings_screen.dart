import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/settings/regions.dart';
import '../../core/settings/settings_repository.dart';
import '../onboarding/coach.dart';
import '../onboarding/onboarding_providers.dart';
import 'place_categories_screen.dart';
import 'theme_picker.dart';
import 'update_sheet.dart';

/// Settings available in 0.1. The full screen arrives with S15.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(searchEngineProvider).value ?? SearchEngine.google;
    final region = ref.watch(regionProvider).value ?? 'US';
    final settings = ref.read(settingsRepoProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 12, 20, 6), child: Overline('Appearance')),
          const CoachScope(
            tipId: 'settings',
            steps: [
              CoachStep(
                'settings.appearance',
                'Make it yours',
                'Pick a look and whether to follow your phone\'s light or dark setting. The coloured circles show the light and the dark version of each look.',
              ),
              CoachStep(
                'settings.help',
                'Help is always here',
                'Replay the tour, search Help and tips, bring the first-visit tips back, or remove the demo contacts.',
              ),
            ],
            child: SizedBox.shrink(),
          ),
          const CoachTarget(id: 'settings.appearance', child: ThemePicker()),
          const Padding(padding: EdgeInsets.fromLTRB(20, 18, 20, 6), child: Overline('Contacts')),
          Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                DropdownRow<String>(
                  title: 'Phone region',
                  subtitle: 'Used when a number has no country code',
                  value: phoneRegions.containsKey(region) ? region : null,
                  hint: region,
                  items: [for (final e in phoneRegions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => v == null ? null : settings.setRegion(v),
                ),
                const Divider(indent: 16, endIndent: 16),
                DropdownRow<bool>(
                  title: 'Sort names by',
                  value: ref.watch(sortByFirstProvider).value ?? false,
                  items: const [
                    DropdownMenuItem(value: false, child: Text('Last name')),
                    DropdownMenuItem(value: true, child: Text('First name')),
                  ],
                  onChanged: (v) => v == null ? null : settings.setSortByFirst(v),
                ),
                const Divider(indent: 16, endIndent: 16),
                SwitchListTile(
                  value: ref.watch(trackCareerProvider).value ?? true,
                  activeThumbColor: Tokens.brass,
                  onChanged: settings.setTrackCareer,
                  title: Text('Career tracking', style: AppText.body),
                  subtitle: Text(
                    'Suggest job changes from new cards and bounced emails. Each contact can also opt out.',
                    style: AppText.secondary,
                  ),
                ),
                const Divider(indent: 16, endIndent: 16),
                SwitchListTile(
                  value: ref.watch(leadsEnabledProvider).value ?? true,
                  activeThumbColor: Tokens.brass,
                  onChanged: settings.setLeadsEnabled,
                  title: Text('Lead ratings', style: AppText.body),
                  subtitle: Text(
                    'Hot, Warm and Cold on contacts. Off hides them everywhere.',
                    style: AppText.secondary,
                  ),
                ),
                const Divider(indent: 16, endIndent: 16),
                DropdownRow<SearchEngine>(
                  title: 'Search engine for web checks',
                  subtitle: 'Web checks open in your default browser',
                  value: engine,
                  items: [for (final e in SearchEngine.values) DropdownMenuItem(value: e, child: Text(e.label))],
                  onChanged: (v) => v == null ? null : settings.setSearchEngine(v),
                ),
              ],
            ),
          ),
          Panel(
            padding: EdgeInsets.zero,
            child: ListTile(
              title: Text('Place categories', style: AppText.body),
              subtitle: Text('Store, Restaurant, Vendor and your own', style: AppText.secondary),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PlaceCategoriesScreen())),
            ),
          ),
          Panel(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              value: ref.watch(autoSaveCleanProvider).value ?? true,
              activeThumbColor: Tokens.brass,
              onChanged: settings.setAutoSaveClean,
              title: Text('Save clear cards automatically', style: AppText.body),
              subtitle: Text(
                'In Batch and Pile scanning, cards read with high confidence go straight to Contacts. The rest wait in the review queue.',
                style: AppText.secondary,
              ),
            ),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(20, 18, 20, 6), child: Overline('Updates')),
          Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  title: Text('Check for updates', style: AppText.body),
                  subtitle: Text("Looks at CardKeep's releases on GitHub", style: AppText.secondary),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showUpdateSheet(context),
                ),
                const Divider(indent: 16, endIndent: 16),
                SwitchListTile(
                  value: ref.watch(updateOnStartProvider).value ?? false,
                  activeThumbColor: Tokens.brass,
                  onChanged: settings.setUpdateOnStart,
                  title: Text('Check when CardKeep opens', style: AppText.body),
                  subtitle: Text(
                    'Off by default. This is the only time CardKeep goes online; it contacts GitHub and sends nothing about you.',
                    style: AppText.secondary,
                  ),
                ),
              ],
            ),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(20, 18, 20, 6), child: Overline('Privacy')),
          Panel(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              value: ref.watch(hideInRecentsProvider).value ?? false,
              activeThumbColor: Tokens.brass,
              onChanged: settings.setHideInRecents,
              title: Text('Hide in recent apps', style: AppText.body),
              subtitle: Text(
                'Blanks CardKeep in the app switcher and blocks screenshots. A preview saved before you turn it on clears the next time you leave CardKeep.',
                style: AppText.secondary,
              ),
            ),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(20, 18, 20, 6), child: Overline('Help')),
          CoachTarget(
            id: 'settings.help',
            child: Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    title: Text('Help & tips', style: AppText.body),
                    subtitle: Text('Short guides and answers, searchable', style: AppText.secondary),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/help'),
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    title: Text('Replay the tour', style: AppText.body),
                    subtitle: Text('Permissions, set-up and the eight lessons again', style: AppText.secondary),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/welcome?replay=1'),
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    title: Text('Reset tips', style: AppText.body),
                    subtitle: Text('Show the first-visit tips again', style: AppText.secondary),
                    onTap: () async {
                      await settings.resetTips();
                      if (context.mounted) {
                        showMessage(context, 'Tips will show again the next time you open each screen');
                      }
                    },
                  ),
                  if ((ref.watch(demoCountProvider).value ?? 0) > 0) ...[
                    const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      title: Text('Remove demo data', style: AppText.body),
                      subtitle: Text(
                        'Deletes the ${ref.watch(demoCountProvider).value} sample contacts tagged Demo',
                        style: AppText.secondary,
                      ),
                      onTap: () async {
                        final ok = await confirm(
                          context,
                          title: 'Remove demo data?',
                          message: 'The sample contacts tagged Demo are deleted. Your own contacts are not touched.',
                          action: 'Remove',
                          destructive: true,
                        );
                        if (!ok) return;
                        final n = await ref.read(demoDataProvider).remove();
                        if (context.mounted) showMessage(context, 'Removed $n demo contacts');
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(20, 18, 20, 6), child: Overline('About')),
          Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                FutureBuilder(
                  future: PackageInfo.fromPlatform(),
                  builder: (_, s) => ListTile(
                    title: Text('Version', style: AppText.body),
                    trailing: Text(
                      s.data == null ? '' : '${s.data!.version} (${s.data!.buildNumber})',
                      style: AppText.secondary,
                    ),
                  ),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  title: Text('Privacy', style: AppText.body),
                  subtitle: Text(
                    'No account, no cloud, no analytics. Your contacts stay on this phone.',
                    style: AppText.secondary,
                  ),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  title: Text('Open-source licences', style: AppText.body),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showLicensePage(context: context, applicationName: 'CardKeep'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
