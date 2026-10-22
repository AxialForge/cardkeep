import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/db/database.dart';
import 'core/transfer/backup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Error messages can carry contact details: none reach the release log (MOB-SEC-0007).
  if (kReleaseMode) debugPrint = (String? message, {int? wrapWidth}) {};
  // A restore chosen last time is swapped in before the database opens (S13.9).
  try {
    lastRestoreOutcome = await applyPendingRestore(await getApplicationDocumentsDirectory());
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
  runApp(
    ProviderScope(overrides: [databaseProvider.overrideWithValue(AppDatabase())], child: const CardOrganizerApp()),
  );
}
