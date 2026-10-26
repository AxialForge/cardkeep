import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/db/database.dart';
import 'core/db/pre_upgrade_copy.dart';
import 'core/lock/lock_controller.dart';
import 'core/platform/platform_info.dart';
import 'core/settings/settings_repository.dart';
import 'core/transfer/backup.dart';
import 'features/desktop/desktop_window.dart';
import 'features/startup/upgrade_failed_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Error messages can carry contact details: none reach the release log (MOB-SEC-0007).
  if (kReleaseMode) debugPrint = (String? message, {int? wrapWidth}) {};
  // A restore chosen last time is swapped in before the database opens (S13.9).
  final docs = await getApplicationDocumentsDirectory();
  try {
    lastRestoreOutcome = await applyPendingRestore(docs);
  } catch (e) {
    // Resumes safely on the next start; the app says so.
    debugPrint('Restore failed: $e');
    lastRestoreOutcome = RestoreOutcome.failed;
  }
  // Bundled fonts are OFL; list them on the licences page.
  LicenseRegistry.addLicense(() async* {
    for (final f in ['Newsreader', 'HankenGrotesk']) {
      yield LicenseEntryWithLineBreaks([f], await rootBundle.loadString('assets/fonts/OFL-$f.txt'));
    }
  });
  // A byte-for-byte copy of the library before SQLite upgrades it, so an upgrade can never cost anything.
  try {
    await copyBeforeUpgrade(docs, targetVersion: AppDatabase.currentSchemaVersion);
  } catch (e) {
    debugPrint('Copy before upgrade failed: $e');
  }
  final db = AppDatabase();
  // Run the upgrade now, so a failure shows a clear screen instead of an empty app.
  try {
    await db.doWhenOpened((_) async {});
  } catch (e) {
    runApp(UpgradeFailedApp(docs: docs, error: e));
    return;
  }
  // App lock on: open locked from the very first frame (S15.2).
  var locked = false;
  try {
    locked = await SettingsRepository(db).appLock();
  } catch (_) {}
  if (PlatformInfo.isDesktop) {
    // Opens the window where it was last time (S16.11).
    try {
      await DesktopWindow.init(SettingsRepository(db));
    } catch (e) {
      debugPrint('Window setup failed: $e');
    }
  }
  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), initialLockedProvider.overrideWithValue(locked)],
      child: const CardOrganizerApp(),
    ),
  );
}
