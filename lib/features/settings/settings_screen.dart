import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/settings/regions.dart';
import '../../core/settings/settings_repository.dart';
import '../onboarding/coach.dart';
import '../onboarding/onboarding_providers.dart';
import '../transfer/transfer_screens.dart';
import 'app_lock_tiles.dart';
import 'delete_everything_dialog.dart';
import 'place_categories_screen.dart';
import 'settings_widgets.dart';
import 'theme_picker.dart';
import 'update_sheet.dart';

/// The sections of Settings, in order, for the jump list at the top.
const settingsSections = [
  'Appearance',
  'Contacts',
  'Reminders',
  'Privacy',
  'Backups',
  'Data',
  'Updates',
  'Help',
  'About',
];

/// Settings (S15.1): grouped, with a row of jump chips so a section is one tap away.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _keys = {for (final s in settingsSections) s: GlobalKey()};

  void _jump(String section) {
    final ctx = _keys[section]!.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Widget _heading(String section, {double top = 18}) =>
      Padding(key: _keys[section], padding: EdgeInsets.fromLTRB(20, top, 20, 6), child: Overline(section));

  @override
  Widget build(BuildContext context) {
    final engine = ref.watch(searchEngineProvider).value ?? SearchEngine.google;
    final region = ref.watch(regionProvider).value ?? 'US';
    final settings = ref.read(settingsRepoProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final s in settingsSections)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(label: Text(s), onPressed: () => _jump(s)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _heading('Appearance', top: 4),
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
                  _heading('Contacts'),
                  Panel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        DropdownRow<String>(
                          title: 'Phone region',
                          subtitle: 'Used when a number has no country code',
                          value: phoneRegions.containsKey(region) ? region : null,
                          hint: region,
                          items: [
                            for (final e in phoneRegions.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                          ],
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
                          items: [
                            for (final e in SearchEngine.values) DropdownMenuItem(value: e, child: Text(e.label)),
                          ],
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
                          Navigator.of(context)
                              .push(MaterialPageRoute<void>(builder: (_) => const PlaceCategoriesScreen())),
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
                        'In Batch, Pile and Sweep scanning, cards read with high confidence go straight to Contacts. The rest wait in the review queue.',
                        style: AppText.secondary,
                      ),
                    ),
                  ),
                  _heading('Reminders'),
                  const Panel(padding: EdgeInsets.zero, child: ReminderTimeRow()),
                  _heading('Privacy'),
                  Panel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        const AppLockTiles(),
                        const Divider(indent: 16, endIndent: 16),
                        SwitchListTile(
                          value: ref.watch(hideInRecentsProvider).value ?? false,
                          activeThumbColor: Tokens.brass,
                          onChanged: settings.setHideInRecents,
                          title: Text('Hide in recent apps', style: AppText.body),
                          subtitle: Text(
                            'Blanks CardKeep in the app switcher and blocks screenshots. A preview saved before you turn it on clears the next time you leave CardKeep.',
                            style: AppText.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _heading('Backups'),
                  Panel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        const BackupScheduleRow(),
                        const Divider(indent: 16, endIndent: 16),
                        const _BackupNow(),
                        const Divider(indent: 16, endIndent: 16),
                        ListTile(
                          title: Text('Where they are kept', style: AppText.body),
                          subtitle: Text(
                            'On this phone, in CardKeep\'s private storage: no other app can read them, and they go if you uninstall CardKeep. Use Export and backup, then Save to…, for a copy you keep somewhere else.',
                            style: AppText.secondary,
                          ),
                        ),
                        const Divider(indent: 16, endIndent: 16),
                        ListTile(
                          title: Text('Export, share and restore', style: AppText.body),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/export'),
                        ),
                        const Divider(indent: 16, endIndent: 16),
                        SwitchListTile(
                          value: ref.watch(exportNotesProvider).value ?? true,
                          activeThumbColor: Tokens.brass,
                          onChanged: settings.setExportNotes,
                          title: Text('Include notes when exporting', style: AppText.body),
                          subtitle: Text('What the Export screen starts with', style: AppText.secondary),
                        ),
                        const Divider(indent: 16, endIndent: 16),
                        SwitchListTile(
                          value: ref.watch(exportImagesProvider).value ?? false,
                          activeThumbColor: Tokens.brass,
                          onChanged: settings.setExportImages,
                          title: Text('Include card photos when exporting', style: AppText.body),
                          subtitle: Text('Makes a .zip with the file and the photos', style: AppText.secondary),
                        ),
                      ],
                    ),
                  ),
                  _heading('Data'),
                  Panel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        const PurgeDaysRow(),
                        const Divider(indent: 16, endIndent: 16),
                        ListTile(
                          title: Text('Delete everything', style: AppText.body.copyWith(color: Tokens.hotFg)),
                          subtitle: Text(
                            'Removes every contact, card photo and backup CardKeep keeps on this phone. Asks you to type DELETE first.',
                            style: AppText.secondary,
                          ),
                          onTap: () => showDeleteEverything(context, ref),
                        ),
                      ],
                    ),
                  ),
                  _heading('Updates'),
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
                  _heading('Help'),
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
                                  message:
                                      'The sample contacts tagged Demo are deleted. Your own contacts are not touched.',
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
                  _heading('About'),
                  Panel(
                    padding: EdgeInsets.zero,
                    child: FutureBuilder(
                      future: PackageInfo.fromPlatform(),
                      builder: (_, s) => ListTile(
                        title: Text('About CardKeep', style: AppText.body),
                        subtitle: Text(
                          s.data == null
                              ? 'Version, privacy, changelog and licences'
                              : 'Version ${s.data!.version} (${s.data!.buildNumber}) · privacy · changelog · licences',
                          style: AppText.secondary,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/about'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Back up now": makes a backup on the phone and says when the last one was made.
class _BackupNow extends ConsumerStatefulWidget {
  const _BackupNow();

  @override
  ConsumerState<_BackupNow> createState() => _BackupNowState();
}

class _BackupNowState extends ConsumerState<_BackupNow> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      final b = await ref.read(backupsProvider.future);
      await b.backupNow(appVersion: (await PackageInfo.fromPlatform()).version);
      if (mounted) showMessage(context, 'Backup made on this phone');
    } catch (_) {
      if (mounted) {
        showMessage(context, 'The backup could not be made. Check that the phone has free storage, then try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final files = ref.watch(backupsProvider).value?.listAuto() ?? const [];
    final last = files.isEmpty ? null : files.first.statSync().modified;
    return ListTile(
      title: Text('Back up now', style: AppText.body),
      subtitle: Text(
        _busy
            ? 'Making a backup…'
            : last == null
            ? 'No backup on this phone yet'
            : 'Last one: ${DateFormat('MMM d, y h:mm a').format(last)}',
        style: AppText.secondary,
      ),
      trailing: _busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.backup_outlined),
      onTap: _busy ? null : _run,
    );
  }
}
