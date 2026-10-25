import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/data/delete_everything.dart';
import '../../core/followups/reminders.dart';
import '../../core/transfer/transfer_repository.dart';
import '../transfer/transfer_screens.dart';

/// The word the person must type to confirm.
const deleteWord = 'DELETE';

/// True when [typed] is the confirmation word, however it was capitalised.
bool isDeleteWord(String typed) => typed.trim().toUpperCase() == deleteWord;

/// Settings > Data > Delete everything (S15.7): says exactly what goes, offers a
/// backup first, and needs the word DELETE typed.
Future<void> showDeleteEverything(BuildContext context, WidgetRef ref) async {
  final choice = await showDialog<bool>(context: context, builder: (_) => const _DeleteEverythingDialog());
  if (choice == null || !context.mounted) return;
  final db = ref.read(databaseProvider);
  final docs = await getApplicationDocumentsDirectory();
  final r = await deleteEverything(db, docs, resetSettings: choice);
  await Reminders.sync(const []).catchError((Object _) {});
  ref.invalidate(imageStoreProvider);
  ref.invalidate(backupsProvider);
  ref.invalidate(cardQueueProvider);
  if (!context.mounted) return;
  context.go('/');
  showMessage(context, 'Everything was deleted: ${r.people} contacts and ${r.files} files');
}

class _DeleteEverythingDialog extends ConsumerStatefulWidget {
  const _DeleteEverythingDialog();

  @override
  ConsumerState<_DeleteEverythingDialog> createState() => _DeleteEverythingDialogState();
}

class _DeleteEverythingDialogState extends ConsumerState<_DeleteEverythingDialog> {
  final _typed = TextEditingController();
  bool _resetSettings = false, _saving = false;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _saveCopy() async {
    setState(() => _saving = true);
    try {
      final b = await ref.read(backupsProvider.future);
      final bytes = await b.create();
      final t = DateTime.now();
      final name =
          'CardKeep backup ${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}.zip';
      if (mounted) await deliver(context, ExportFile(name, 'application/zip', bytes, 1), save: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = isDeleteWord(_typed.text);
    return AlertDialog(
      backgroundColor: Tokens.surface,
      title: Text('Delete everything?', style: AppText.heading),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This removes every contact, company, place, tag, event, follow-up and card photo from this phone, the review queue, and the backups and fallback copies CardKeep keeps here. It also unpairs your PC: the PC keeps its own copy, but it can no longer sync with this phone until you pair again.',
              style: AppText.body,
            ),
            const SizedBox(height: 8),
            Text(
              'It cannot be undone. A backup you saved somewhere else with "Save to…" is yours and is not touched.',
              style: AppText.secondary,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _saving ? null : _saveCopy,
              icon: const Icon(Icons.save_alt),
              label: Text(_saving ? 'Making a backup…' : 'Save a backup first'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _resetSettings,
              onChanged: (v) => setState(() => _resetSettings = v ?? false),
              title: Text('Also reset my settings', style: AppText.body),
              subtitle: Text(
                'Look, name order, region, lock and the rest go back to how they started.',
                style: AppText.secondary,
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _typed,
              autofocus: false,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Type DELETE to confirm'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: ready ? () => Navigator.pop(context, _resetSettings) : null,
          child: Text('Delete everything', style: TextStyle(color: ready ? Tokens.hotFg : Tokens.ink2)),
        ),
      ],
    );
  }
}
