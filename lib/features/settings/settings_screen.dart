import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/settings/settings_repository.dart';

const _regions = {
  'US': 'United States', 'CA': 'Canada', 'MX': 'Mexico', 'GB': 'United Kingdom',
  'IE': 'Ireland', 'DE': 'Germany', 'FR': 'France', 'IT': 'Italy', 'ES': 'Spain',
  'NL': 'Netherlands', 'AU': 'Australia', 'IN': 'India', 'JP': 'Japan', 'CN': 'China',
};

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
      body: ListView(children: [
        const Padding(padding: EdgeInsets.fromLTRB(20, 12, 20, 6), child: Overline('Contacts')),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            ListTile(
              title: Text('Phone region', style: AppText.body),
              subtitle: Text('Used when a number has no country code', style: AppText.secondary),
              trailing: DropdownButton<String>(
                value: _regions.containsKey(region) ? region : null,
                hint: Text(region),
                underline: const SizedBox(),
                items: [
                  for (final e in _regions.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => v == null ? null : settings.setRegion(v),
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
          ]),
        ),
        const Padding(padding: EdgeInsets.fromLTRB(20, 18, 20, 6), child: Overline('About')),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            FutureBuilder(
              future: PackageInfo.fromPlatform(),
              builder: (_, s) => ListTile(
                title: Text('Version', style: AppText.body),
                trailing: Text(s.data == null ? '' : '${s.data!.version} (${s.data!.buildNumber})',
                    style: AppText.secondary),
              ),
            ),
            const Divider(indent: 16, endIndent: 16),
            ListTile(
              title: Text('Privacy', style: AppText.body),
              subtitle: Text(
                  'No account, no cloud, no analytics. Your contacts stay on this phone.',
                  style: AppText.secondary),
            ),
            const Divider(indent: 16, endIndent: 16),
            ListTile(
              title: Text('Open-source licences', style: AppText.body),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(context: context, applicationName: 'CardKeep'),
            ),
          ]),
        ),
      ]),
    );
  }
}
