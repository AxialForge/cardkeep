import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/theme_family.dart';
import '../../app/widgets.dart';
import '../../core/settings/settings_repository.dart';
import '../../kit/theme_pill.dart';
import 'place_categories_screen.dart';
import 'update_sheet.dart';

const _regions = {
  'US': 'United States',
  'CA': 'Canada',
  'MX': 'Mexico',
  'GB': 'United Kingdom',
  'IE': 'Ireland',
  'DE': 'Germany',
  'FR': 'France',
  'IT': 'Italy',
  'ES': 'Spain',
  'NL': 'Netherlands',
  'AU': 'Australia',
  'IN': 'India',
  'JP': 'Japan',
  'CN': 'China',
};

/// Settings available in 0.1. The full screen arrives with S15.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(searchEngineProvider).value ?? SearchEngine.google;
    final region = ref.watch(regionProvider).value ?? 'US';
    final settings = ref.read(settingsRepoProvider);
    final choice = ref.watch(themeChoiceProvider).value ?? AppPalette.systemId;
    final platform = MediaQuery.platformBrightnessOf(context);
    final theme = ThemeChoice.parse(choice);
    final shownBrightness = switch (theme.mode) {
      ThemeMode.system => platform,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.light => Brightness.light,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 12, 20, 6), child: Overline('Appearance')),
          Panel(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              value: theme.mode == ThemeMode.system,
              activeThumbColor: Tokens.brass,
              onChanged: (on) => settings.setTheme(
                theme
                    .withMode(on ? ThemeMode.system : (platform == Brightness.dark ? ThemeMode.dark : ThemeMode.light))
                    .id,
              ),
              title: Text('Match phone', style: AppText.body),
              subtitle: Text("Light or Dark, following your phone's setting", style: AppText.secondary),
            ),
          ),
          const SizedBox(height: 6),
          for (final f in ThemeFamily.all)
            ThemePill(
              name: f.label,
              lightColors: f.bubbles(f.light),
              darkColors: f.bubbles(f.dark),
              surface: Tokens.surface,
              hairline: Tokens.hairline,
              ink: Tokens.ink,
              accent: f.forBrightness(shownBrightness).accent,
              nameStyle: AppText.heading,
              selected: f == theme.family,
              pinned: f == theme.family && theme.mode != ThemeMode.system ? theme.mode : null,
              onSelectTheme: () => settings.setTheme(theme.withFamily(f).id),
              onSelectLight: () => settings.setTheme(ThemeChoice(f, ThemeMode.light).id),
              onSelectDark: () => settings.setTheme(ThemeChoice(f, ThemeMode.dark).id),
            ),
          const Padding(padding: EdgeInsets.fromLTRB(20, 18, 20, 6), child: Overline('Contacts')),
          Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  title: Text('Phone region', style: AppText.body),
                  subtitle: Text('Used when a number has no country code', style: AppText.secondary),
                  trailing: DropdownButton<String>(
                    value: _regions.containsKey(region) ? region : null,
                    hint: Text(region),
                    underline: const SizedBox(),
                    items: [for (final e in _regions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => v == null ? null : settings.setRegion(v),
                  ),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  title: Text('Sort names by', style: AppText.body),
                  trailing: DropdownButton<bool>(
                    value: ref.watch(sortByFirstProvider).value ?? false,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: false, child: Text('Last name')),
                      DropdownMenuItem(value: true, child: Text('First name')),
                    ],
                    onChanged: (v) => v == null ? null : settings.setSortByFirst(v),
                  ),
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
                ListTile(
                  title: Text('Search engine for web checks', style: AppText.body),
                  subtitle: Text('Web checks open in your default browser', style: AppText.secondary),
                  trailing: DropdownButton<SearchEngine>(
                    value: engine,
                    underline: const SizedBox(),
                    items: [for (final e in SearchEngine.values) DropdownMenuItem(value: e, child: Text(e.label))],
                    onChanged: (v) => v == null ? null : settings.setSearchEngine(v),
                  ),
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
