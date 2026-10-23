import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/drawer.dart';
import '../../app/plural.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/db/database.dart';
import '../../core/dupes/duplicates_repository.dart';
import '../../core/tags/tags_repository.dart';
import '../../core/transfer/backup.dart';
import '../../core/transfer/csv_import.dart';
import '../../core/transfer/transfer_repository.dart';
import '../../core/vcard/vcard.dart';
import '../../core/vcard/vcard_reader.dart';
import '../events/events_screens.dart';
import '../tags/tags_screen.dart';

final transferRepoProvider = Provider((ref) {
  final db = ref.watch(databaseProvider), contacts = ref.watch(contactsRepoProvider);
  return TransferRepository(
    db,
    contacts,
    DuplicatesRepository(db, contacts),
    ref.watch(careerRepoProvider),
    TagsRepository(db, contacts),
  );
});

final backupsProvider = FutureProvider<Backups>(
  (ref) async => Backups(ref.watch(databaseProvider), await getApplicationDocumentsDirectory()),
);

/// Share sheet, or "Save to…" through Android's file picker (S13.3).
Future<void> deliver(BuildContext context, ExportFile f, {required bool save}) async {
  if (save) {
    final uri = await FilePicker.saveFile(fileName: f.name, bytes: f.bytes, mimeType: f.mime);
    if (uri != null && context.mounted) showMessage(context, 'Saved ${f.name}');
    return;
  }
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(f.bytes, name: f.name, mimeType: f.mime)],
      fileNameOverrides: [f.name],
    ),
  );
}

Future<String> _appVersion() async => (await PackageInfo.fromPlatform()).version;

/// Export and backup (mockup Export, S13.1-S13.3, S13.8-S13.10).
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});
  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  String _scope = 'all'; // all | tag:<id> | event:<id>
  ExportFormat _format = ExportFormat.vcard3;
  bool _notes = true, _images = false, _busy = false;

  ExportScope get _scopeValue => switch (_scope.split(':')) {
    ['tag', final id] => ScopeTag(id),
    ['event', final id] => ScopeEvent(id),
    _ => const ScopeEveryone(),
  };

  Future<void> _export({required bool save}) async {
    setState(() => _busy = true);
    try {
      final f = await ref
          .read(transferRepoProvider)
          .export(
            _scopeValue,
            _format,
            notes: _notes,
            images: _images,
            store: await ref.read(imageStoreProvider.future),
          );
      if (!mounted) return;
      if (f.count == 0) return showMessage(context, 'No one to export.');
      await deliver(context, f, save: save);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backup({required bool save}) async {
    setState(() => _busy = true);
    try {
      final b = await ref.read(backupsProvider.future);
      final bytes = await b.create(appVersion: await _appVersion());
      final t = DateTime.now();
      final name = 'CardKeep backup ${DateFormat('yyyy-MM-dd HHmm').format(t)}.zip';
      if (mounted) await deliver(context, ExportFile(name, 'application/zip', bytes, 1), save: save);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(tagsProvider).value ?? const <TagView>[];
    final events = ref.watch(eventsProvider).value ?? const <Event>[];
    final settings = ref.read(settingsRepoProvider);
    return Scaffold(
      drawer: const AppDrawer(current: '/export'),
      appBar: AppBar(title: const Text('Export and backup')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 6), child: Overline('Export contacts')),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _scope,
                    decoration: const InputDecoration(labelText: 'Who'),
                    items: [
                      const DropdownMenuItem(value: 'all', child: Text('Everyone')),
                      for (final t in tags) DropdownMenuItem(value: 'tag:${t.id}', child: Text('Tag: ${t.name}')),
                      for (final e in events)
                        DropdownMenuItem(value: 'event:${e.uuid}', child: Text('Event: ${e.name}')),
                    ],
                    onChanged: (v) => setState(() => _scope = v ?? 'all'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ExportFormat>(
                    initialValue: _format,
                    decoration: const InputDecoration(labelText: 'Format'),
                    items: [for (final f in ExportFormat.values) DropdownMenuItem(value: f, child: Text(f.label))],
                    onChanged: (v) => setState(() => _format = v ?? ExportFormat.vcard3),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _notes,
                    onChanged: (v) => setState(() => _notes = v),
                    title: const Text('Include notes'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _images,
                    onChanged: (v) => setState(() => _images = v),
                    title: const Text('Include card photos'),
                    subtitle: const Text('Makes a .zip with the file and the photos'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _export(save: true),
                          icon: const Icon(Icons.save_alt),
                          label: const Text('Save to…'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _export(save: false),
                          icon: const Icon(Icons.ios_share),
                          label: const Text('Share'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Padding(padding: EdgeInsets.fromLTRB(20, 18, 20, 6), child: Overline('Backup')),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Everything in one file: contacts, card photos, tags, events and settings. Keep it somewhere safe, '
                    'like Google Drive or a computer.',
                    style: AppText.secondary,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _backup(save: true),
                          icon: const Icon(Icons.save_alt),
                          label: const Text('Save to…'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _backup(save: false),
                          icon: const Icon(Icons.backup_outlined),
                          label: const Text('Back up now'),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: ref.watch(autoBackupProvider).value ?? false,
                    onChanged: settings.setAutoBackup,
                    title: const Text('Weekly backup on this phone'),
                    subtitle: const Text('Made when you open CardKeep and one is due. The last 4 are kept.'),
                  ),
                  const _AutoBackups(),
                  const Divider(),
                  TextButton.icon(
                    onPressed: () => restoreFrom(context, ref, null),
                    icon: const Icon(Icons.settings_backup_restore),
                    label: const Text('Restore from a backup file…'),
                  ),
                  const _Fallback(),
                ],
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

class _AutoBackups extends ConsumerStatefulWidget {
  const _AutoBackups();
  @override
  ConsumerState<_AutoBackups> createState() => _AutoBackupsState();
}

class _AutoBackupsState extends ConsumerState<_AutoBackups> {
  @override
  Widget build(BuildContext context) {
    final b = ref.watch(backupsProvider).value;
    final files = b?.listAuto() ?? const <File>[];
    if (files.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final f in files)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(p.basenameWithoutExtension(f.path).replaceFirst('CardKeep backup ', '')),
            subtitle: Text('${(f.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB'),
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                final bytes = await f.readAsBytes();
                if (!context.mounted) return;
                if (v == 'restore') return restoreFrom(context, ref, bytes);
                await deliver(context, ExportFile(p.basename(f.path), 'application/zip', bytes, 1), save: v == 'save');
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'save', child: Text('Save to…')),
                PopupMenuItem(value: 'share', child: Text('Share')),
                PopupMenuItem(value: 'restore', child: Text('Restore this backup')),
              ],
            ),
          ),
      ],
    );
  }
}

/// The data from before the last restore: go back to it, or discard it
/// (audit MOB-REL-0003, MOB-PRV-0003). Removed by itself after 30 days.
class _Fallback extends ConsumerStatefulWidget {
  const _Fallback();
  @override
  ConsumerState<_Fallback> createState() => _FallbackState();
}

class _FallbackState extends ConsumerState<_Fallback> {
  @override
  Widget build(BuildContext context) {
    final b = ref.watch(backupsProvider).value;
    final made = b?.fallbackDate();
    if (b == null || made == null) return const SizedBox.shrink();
    final mb = (b.fallbackBytes() / 1024 / 1024).toStringAsFixed(1);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history),
      title: const Text('Data from before the last restore'),
      subtitle: Text('${DateFormat('MMM d, y').format(made)} · $mb MB · removed after ${fallbackKeep.inDays} days'),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'back') {
            final ok = await confirm(
              context,
              title: 'Go back to this data?',
              message:
                  'CardKeep swaps it with what you have now (which is kept as the fallback copy instead). '
                  'CardKeep closes to finish; open it again.',
              action: 'Go back',
              destructive: true,
            );
            if (!ok) return;
            await b.stageFallback();
            exit(0);
          }
          if (!context.mounted) return;
          final ok = await confirm(
            context,
            title: 'Discard this copy?',
            message: 'It is deleted from this phone. Your current data is not touched.',
            action: 'Discard',
            destructive: true,
          );
          if (!ok) return;
          await b.discardFallback();
          if (mounted) setState(() {});
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'back', child: Text('Go back to it')),
          PopupMenuItem(value: 'discard', child: Text('Discard')),
        ],
      ),
    );
  }
}

/// Restore (S13.9): checked first, confirmed, then applied on restart.
Future<void> restoreFrom(BuildContext context, WidgetRef ref, Uint8List? bytes) async {
  if (bytes == null) {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
    if (picked.isEmpty) return;
    bytes = await picked.single.readAsBytes();
  }
  final b = await ref.read(backupsProvider.future);
  final BackupInfo info;
  try {
    info = b.check(bytes);
  } on BackupException catch (e) {
    if (context.mounted) showMessage(context, e.message);
    return;
  }
  if (!context.mounted) return;
  final ok = await confirm(
    context,
    title: 'Restore this backup?',
    message:
        'From ${DateFormat('MMM d, y h:mm a').format(info.created)}: ${plural(info.people, 'contact')}, ${plural(info.cards, 'card')}.\n\n'
        'It replaces everything in CardKeep now. Your current data is kept as a fallback copy. CardKeep closes to '
        'finish; open it again.',
    action: 'Restore',
    destructive: true,
  );
  if (!ok) return;
  try {
    await b.stage(bytes);
  } on BackupException catch (e) {
    if (context.mounted) showMessage(context, e.message);
    return;
  }
  // The swap happens before the database opens, so the app must restart.
  exit(0);
}

/// Import (mockup Import, S13.4-S13.7).
class ImportScreen extends ConsumerStatefulWidget {
  final Uint8List? vcf; // a .vcf opened from another app
  const ImportScreen({super.key, this.vcf});
  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  bool _busy = false;
  ImportSummary? _last;

  @override
  void initState() {
    super.initState();
    if (widget.vcf != null) WidgetsBinding.instance.addPostFrameCallback((_) => _importVcf(widget.vcf!));
  }

  Future<void> _run(Future<ImportSummary> Function() job) async {
    setState(() => _busy = true);
    try {
      final s = await job();
      if (mounted) setState(() => _last = s);
    } catch (e) {
      if (mounted) showMessage(context, 'Could not import: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importVcf(Uint8List bytes) async {
    final list = readVCards(utf8.decode(bytes, allowMalformed: true));
    if (list.isEmpty) return showMessage(context, 'No contacts found in that file.');
    final ok = await confirm(
      context,
      title: 'Import ${plural(list.length, 'contact')}?',
      message: 'Each is tagged Imported. Someone you already have is updated instead of added twice.',
      action: 'Import',
    );
    if (!ok) return;
    await _run(
      () => ref.read(transferRepoProvider).importContacts(list, region: ref.read(regionProvider).value ?? 'US'),
    );
  }

  Future<void> _pickVcf() async {
    final f = await FilePicker.pickFiles(type: FileType.any);
    if (f.isEmpty) return;
    await _importVcf(await f.single.readAsBytes());
  }

  Future<void> _pickCsv() async {
    final f = await FilePicker.pickFiles(type: FileType.any);
    if (f.isEmpty || !mounted) return;
    final rows = parseCsv(utf8.decode(await f.single.readAsBytes(), allowMalformed: true));
    if (!mounted) return;
    if (rows.length < 2) return showMessage(context, 'That file has no rows to import.');
    final list = await context.push<List<ExportContact>>('/import/csv', extra: rows);
    if (list == null || list.isEmpty) return;
    await _run(
      () => ref.read(transferRepoProvider).importContacts(list, region: ref.read(regionProvider).value ?? 'US'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _last;
    return Scaffold(
      drawer: const AppDrawer(current: '/import'),
      appBar: AppBar(title: const Text('Import')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          children: [
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.contact_page_outlined),
                    title: const Text('vCard file (.vcf)'),
                    subtitle: const Text('From Google Contacts, Outlook, an iPhone or LinkedIn'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickVcf,
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.table_chart_outlined),
                    title: const Text('Spreadsheet (.csv)'),
                    subtitle: const Text('You choose which column is which'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickCsv,
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.settings_backup_restore),
                    title: const Text('CardKeep backup (.zip)'),
                    subtitle: const Text('Replaces everything with the backup'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => restoreFrom(context, ref, null),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                'Imported contacts get the Imported tag. Someone you already have is updated, not added twice; someone '
                'now at another company shows up in Career moves.',
                style: AppText.secondary,
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (s != null)
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Overline('Imported'),
                    const SizedBox(height: 6),
                    Text('${s.added} new, ${s.merged} updated, ${s.skipped} already there', style: AppText.bodyStrong),
                    if (s.jobChanges > 0)
                      Text(
                        '${s.jobChanges} possible job change${s.jobChanges == 1 ? '' : 's'} in Career moves',
                        style: AppText.secondary,
                      ),
                    const SizedBox(height: 8),
                    TextButton(onPressed: () => context.go('/'), child: const Text('Go to Contacts')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// CSV column matching with a 5-row preview (S13.5). Returns the contacts.
class CsvMappingScreen extends ConsumerStatefulWidget {
  final List<List<String>> rows; // header first
  const CsvMappingScreen({super.key, required this.rows});
  @override
  ConsumerState<CsvMappingScreen> createState() => _CsvMappingScreenState();
}

class _CsvMappingScreenState extends ConsumerState<CsvMappingScreen> {
  late List<CsvField> _map = guessMapping(widget.rows.first);

  List<String> get _headers => widget.rows.first;

  @override
  void initState() {
    super.initState();
    ref.read(transferRepoProvider).savedMapping(_headers).then((m) {
      if (m != null && mounted) setState(() => _map = m);
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.rows.skip(1).toList();
    final preview = rowsToContacts(data.take(5).toList(), _map);
    return Scaffold(
      appBar: AppBar(title: Text('Import ${plural(data.length, 'row')}')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.gutter, 8, Tokens.gutter, 12),
          child: FilledButton(
            onPressed: () async {
              await ref.read(transferRepoProvider).saveMapping(_headers, _map);
              if (context.mounted) context.pop(rowsToContacts(data, _map));
            },
            child: const Text('Import'),
          ),
        ),
      ),
      body: ListView(
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 6), child: Overline('Which column is which')),
          Panel(
            child: Column(
              children: [
                for (var i = 0; i < _headers.length; i++)
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_headers[i].isEmpty ? '(column ${i + 1})' : _headers[i], style: AppText.bodyStrong),
                            Text(
                              data.isEmpty || data.first.length <= i ? '' : data.first[i],
                              style: AppText.secondary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      DropdownButton<CsvField>(
                        value: _map[i],
                        underline: const SizedBox(),
                        items: [for (final f in CsvField.values) DropdownMenuItem(value: f, child: Text(f.label))],
                        onChanged: (v) => setState(() => _map = [..._map]..[i] = v ?? CsvField.skip),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(20, 14, 20, 6), child: Overline('Preview')),
          Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (preview.isEmpty) const ListTile(title: Text('Nothing to import with these columns')),
                for (final c in preview)
                  ListTile(
                    title: Text(c.fullName.isEmpty ? '(no name)' : c.fullName, style: AppText.bodyStrong),
                    subtitle: Text(
                      [
                        c.title,
                        c.company,
                        c.emails.firstOrNull,
                        c.phones.firstOrNull?.number,
                      ].whereType<String>().join(' · '),
                      style: AppText.secondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
