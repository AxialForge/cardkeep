import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/settings/settings_repository.dart';

/// "Back up automatically": Off, Weekly or Daily. Shared by Settings and the
/// Export and backup screen so the two never disagree (S13.10, S15.1).
class BackupScheduleRow extends ConsumerWidget {
  const BackupScheduleRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(backupScheduleProvider).value ?? BackupSchedule.off;
    return DropdownRow<BackupSchedule>(
      title: 'Back up automatically',
      subtitle: 'Made when you open CardKeep and one is due. The newest 4 are kept on this phone.',
      value: value,
      items: [for (final s in BackupSchedule.values) DropdownMenuItem(value: s, child: Text(s.label))],
      onChanged: (v) => v == null ? null : ref.read(settingsRepoProvider).setBackupSchedule(v),
    );
  }
}

/// "Follow-up reminders arrive at" with a time picker (S15.1).
class ReminderTimeRow extends ConsumerWidget {
  const ReminderTimeRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minutes = ref.watch(reminderMinutesProvider).value ?? 8 * 60;
    final time = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    return ListTile(
      title: Text('Follow-up reminders arrive at', style: AppText.body),
      subtitle: Text('On the day a follow-up is due', style: AppText.secondary),
      trailing: Text(time.format(context), style: AppText.bodyStrong),
      onTap: () async {
        final picked = await showTimePicker(context: context, initialTime: time, helpText: 'Reminder time');
        if (picked != null) {
          await ref.read(settingsRepoProvider).setReminderMinutes(picked.hour * 60 + picked.minute);
        }
      },
    );
  }
}

/// "Deleted contacts are kept for 7, 14 or 30 days" (S15.1).
class PurgeDaysRow extends ConsumerWidget {
  const PurgeDaysRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(purgeDaysProvider).value ?? 7;
    return DropdownRow<int>(
      title: 'Deleted contacts are kept for',
      subtitle: 'You can undo a delete until then. After that CardKeep wipes the contact and its card photos for good.',
      value: days,
      items: [for (final d in purgeDayChoices) DropdownMenuItem(value: d, child: Text('$d days'))],
      onChanged: (v) => v == null ? null : ref.read(settingsRepoProvider).setPurgeDays(v),
    );
  }
}
