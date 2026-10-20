import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/db/database.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Bundled fonts are OFL; list them on the licences page.
  LicenseRegistry.addLicense(() async* {
    for (final f in ['Newsreader', 'HankenGrotesk']) {
      yield LicenseEntryWithLineBreaks([f], await rootBundle.loadString('assets/fonts/OFL-$f.txt'));
    }
  });
  runApp(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(AppDatabase())],
    child: const CardOrganizerApp(),
  ));
}
