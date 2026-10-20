import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/contacts/contact_models.dart';
import '../core/contacts/contacts_repository.dart';
import '../core/db/database.dart';
import '../core/links/link_launcher.dart';
import '../core/settings/settings_repository.dart';
import 'theme.dart';

/// Overridden in main() and in tests (in-memory database).
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('databaseProvider'));

final contactsRepoProvider = Provider((ref) => ContactsRepository(ref.watch(databaseProvider)));
final settingsRepoProvider = Provider((ref) => SettingsRepository(ref.watch(databaseProvider)));
final launcherProvider = Provider((ref) => LinkLauncher());

class ContactFilterNotifier extends Notifier<ContactFilter> {
  @override
  ContactFilter build() => const ContactFilter();
  void set(ContactFilter f) => state = f;
  void update(ContactFilter Function(ContactFilter) fn) => state = fn(state);
}

final contactFilterProvider = NotifierProvider<ContactFilterNotifier, ContactFilter>(ContactFilterNotifier.new);

final contactsProvider = StreamProvider<List<ContactSummary>>(
  (ref) => ref.watch(contactsRepoProvider).watchContacts(ref.watch(contactFilterProvider)),
);

final statsProvider = StreamProvider<LibraryStats>((ref) => ref.watch(contactsRepoProvider).watchStats());

final contactDetailProvider = StreamProvider.family<ContactDetail?, String>(
  (ref, id) => ref.watch(contactsRepoProvider).watchDetail(id),
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
