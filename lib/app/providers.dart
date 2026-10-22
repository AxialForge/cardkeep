import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/cards/card_queue_repository.dart';
import '../core/career/career_repository.dart';
import '../core/contacts/contact_models.dart';
import '../core/contacts/contacts_repository.dart';
import '../core/db/database.dart';
import '../core/dupes/duplicates_repository.dart';
import '../core/images/image_store.dart';
import '../core/links/link_launcher.dart';
import '../core/settings/settings_repository.dart';
import '../parser/ocr.dart';
import '../parser/ocr_adapter_mlkit.dart';
import '../scan/qr_reader_mlkit.dart';
import '../scan/scan_pipeline.dart';
import 'theme.dart';

/// Overridden in main() and in tests (in-memory database).
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('databaseProvider'));

final contactsRepoProvider = Provider((ref) => ContactsRepository(ref.watch(databaseProvider)));
final careerRepoProvider = Provider((ref) {
  final contacts = ref.watch(contactsRepoProvider);
  return CareerRepository(
    ref.watch(databaseProvider),
    contacts,
    DuplicatesRepository(ref.watch(databaseProvider), contacts),
  );
});
final settingsRepoProvider = Provider((ref) => SettingsRepository(ref.watch(databaseProvider)));
final launcherProvider = Provider((ref) => LinkLauncher());

class ContactFilterNotifier extends Notifier<ContactFilter> {
  @override
  ContactFilter build() => const ContactFilter();
  void set(ContactFilter f) => state = f;
  void update(ContactFilter Function(ContactFilter) fn) => state = fn(state);
}

final contactFilterProvider = NotifierProvider<ContactFilterNotifier, ContactFilter>(ContactFilterNotifier.new);

final sortByFirstProvider = StreamProvider<bool>((ref) => ref.watch(settingsRepoProvider).watchSortByFirst());
final trackCareerProvider = StreamProvider<bool>((ref) => ref.watch(settingsRepoProvider).watchTrackCareer());
final autoBackupProvider = StreamProvider<bool>((ref) => ref.watch(settingsRepoProvider).watchAutoBackup());
final leadsEnabledProvider = StreamProvider<bool>((ref) => ref.watch(settingsRepoProvider).watchLeadsEnabled());

final contactsProvider = StreamProvider<List<ContactSummary>>(
  (ref) => ref
      .watch(contactsRepoProvider)
      .watchContacts(ref.watch(contactFilterProvider), byFirst: ref.watch(sortByFirstProvider).value ?? false),
);

final statsProvider = StreamProvider<LibraryStats>((ref) => ref.watch(contactsRepoProvider).watchStats());

final contactDetailProvider = StreamProvider.family<ContactDetail?, String>(
  (ref, id) => ref.watch(contactsRepoProvider).watchDetail(id),
);

final colleaguesProvider = StreamProvider.family<(String, List<ContactSummary>)?, String>(
  (ref, id) => ref.watch(contactsRepoProvider).watchColleagues(id),
);

final searchEngineProvider = StreamProvider<SearchEngine>((ref) => ref.watch(settingsRepoProvider).watchSearchEngine());

/// Phone region: the saved setting, else the device locale's country, else US.
final regionProvider = StreamProvider<String>(
  (ref) => ref
      .watch(settingsRepoProvider)
      .watchRegion()
      .map((saved) => saved ?? PlatformDispatcher.instance.locale.countryCode ?? 'US'),
);

/// The saved theme choice: a palette id, or [AppPalette.systemId] (the default)
/// to follow the phone's light/dark setting.
final themeChoiceProvider = StreamProvider<String>(
  (ref) => ref.watch(settingsRepoProvider).watchTheme().map((id) => id ?? AppPalette.systemId),
);

/// Card images live under the app's documents folder (never in shared storage).
final imageStoreProvider = FutureProvider<ImageStore>((ref) async {
  final docs = await getApplicationDocumentsDirectory();
  return ImageStore(Directory(p.join(docs.path, 'cards')));
});

/// On-device OCR where ML Kit exists (Android, iOS); null on desktop and in tests.
final ocrAdapterProvider = Provider<OcrAdapter?>((ref) {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return null;
  final a = MlKitOcrAdapter();
  ref.onDispose(a.close);
  return a;
});

/// On-device QR reading where ML Kit exists; null on desktop and in tests.
final qrReaderProvider = Provider<QrReader?>((ref) {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return null;
  final r = MlKitQrReader();
  ref.onDispose(r.close);
  return r;
});

final scanPipelineProvider = FutureProvider<ScanPipeline>(
  (ref) async => ScanPipeline(
    store: await ref.watch(imageStoreProvider.future),
    ocr: ref.watch(ocrAdapterProvider),
    qr: ref.watch(qrReaderProvider),
    region: ref.watch(regionProvider).value ?? 'US',
  ),
);

final updateOnStartProvider = StreamProvider<bool>((ref) => ref.watch(settingsRepoProvider).watchUpdateOnStart());

final autoSaveCleanProvider = StreamProvider<bool>((ref) => ref.watch(settingsRepoProvider).watchAutoSaveClean());

final cardQueueProvider = FutureProvider<CardQueueRepository>(
  (ref) async => CardQueueRepository(ref.watch(databaseProvider), await ref.watch(imageStoreProvider.future)),
);

final queueProvider = StreamProvider<List<QueueItem>>((ref) async* {
  final q = await ref.watch(cardQueueProvider.future);
  yield* q.watchQueue();
});

final queueStatsProvider = StreamProvider<QueueStats>((ref) async* {
  final q = await ref.watch(cardQueueProvider.future);
  yield* q.watchStats();
});
