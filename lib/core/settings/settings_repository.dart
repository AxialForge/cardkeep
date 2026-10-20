import 'package:drift/drift.dart';

import '../db/database.dart';

enum SearchEngine {
  google('Google', 'https://www.google.com/search?q={query}'),
  duckduckgo('DuckDuckGo', 'https://duckduckgo.com/?q={query}'),
  bing('Bing', 'https://www.bing.com/search?q={query}');

  final String label;
  final String template;
  const SearchEngine(this.label, this.template);

  Uri searchUri(String query) => Uri.parse(template.replaceAll('{query}', Uri.encodeQueryComponent(query)));
}

/// Typed access to the app_settings key/value table.
class SettingsRepository {
  final AppDatabase db;
  SettingsRepository(this.db);

  static const _searchEngine = 'search_engine';
  static const _region = 'default_region';
  static const _theme = 'theme';
  static const _updateOnStart = 'update_check_on_start';

  Stream<String?> _watch(String key) =>
      (db.select(db.appSettings)..where((s) => s.key.equals(key))).watchSingleOrNull().map((r) => r?.value);

  Future<void> _set(String key, String value) => db
      .into(db.appSettings)
      .insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value, updatedAt: Value(DateTime.now())));

  Stream<SearchEngine> watchSearchEngine() =>
      _watch(_searchEngine)
          .map((v) => SearchEngine.values.where((e) => e.name == v).firstOrNull ?? SearchEngine.google);
  Future<void> setSearchEngine(SearchEngine e) => _set(_searchEngine, e.name);

  /// Phone region used when a number has no country code. Null = device locale.
  Stream<String?> watchRegion() => _watch(_region);
  Future<void> setRegion(String region) => _set(_region, region);

  /// Off by default: the update check is CardKeep's only internet use.
  Stream<bool> watchUpdateOnStart() => _watch(_updateOnStart).map((v) => v == 'true');
  Future<bool> updateOnStart() async =>
      (await (db.select(db.appSettings)..where((s) => s.key.equals(_updateOnStart))).getSingleOrNull())?.value ==
      'true';
  Future<void> setUpdateOnStart(bool on) => _set(_updateOnStart, '$on');

  /// Colour palette id (see AppPalette). Null = the default palette.
  Stream<String?> watchTheme() => _watch(_theme);
  Future<void> setTheme(String id) => _set(_theme, id);
}
