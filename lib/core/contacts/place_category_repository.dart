import 'package:drift/drift.dart';

import '../db/database.dart';
import 'contact_models.dart';

/// One entry in the place category list (S14b.6).
class PlaceCategoryItem {
  final String id;
  final String label;
  final bool builtIn;
  const PlaceCategoryItem(this.id, this.label, {this.builtIn = false});

  /// "Other" is where places go when their category is deleted; it stays.
  bool get canDelete => id != PlaceCategory.other.name;
}

/// The editable list of place categories. People store the id, so renaming a
/// category changes it everywhere; deleting one moves its places to Other.
class PlaceCategoryRepository {
  final AppDatabase db;

  /// Rebuilds a person's search row after a rename or delete changes the label
  /// their category is found by (ContactsRepository.reindex).
  final Future<void> Function(String personId)? reindex;

  PlaceCategoryRepository(this.db, {this.reindex});

  Stream<List<PlaceCategoryItem>> watchAll() =>
      (db.select(db.placeCategories)
            ..where((c) => c.deletedAt.isNull())
            ..orderBy([(c) => OrderingTerm(expression: c.sort), (c) => OrderingTerm(expression: c.label)]))
          .watch()
          .map(_remember);

  Future<List<PlaceCategoryItem>> all() async => _remember(
    await (db.select(db.placeCategories)
          ..where((c) => c.deletedAt.isNull())
          ..orderBy([(c) => OrderingTerm(expression: c.sort), (c) => OrderingTerm(expression: c.label)]))
        .get(),
  );

  /// Keeps [placeCategoryLabels] in step with the table, for list subtitles,
  /// search and export.
  List<PlaceCategoryItem> _remember(List<PlaceCategoryRow> rows) {
    final items = [for (final r in rows) PlaceCategoryItem(r.id, r.label, builtIn: r.builtIn)];
    for (final i in items) {
      placeCategoryLabels[i.id] = i.label;
    }
    return items;
  }

  /// Adds a category (or returns the one with that label already). Returns its id.
  Future<String> add(String label) async {
    final name = label.trim();
    if (name.isEmpty) throw ArgumentError('A category needs a name');
    final existing = await idForLabel(name);
    if (existing != null) return existing;
    final max = await db
        .customSelect(
          "SELECT COALESCE(MAX(sort), -1) AS m FROM place_categories WHERE deleted_at IS NULL AND id != '${PlaceCategory.other.name}'",
        )
        .getSingle();
    final id = 'c_${DateTime.now().microsecondsSinceEpoch}';
    await db
        .into(db.placeCategories)
        .insert(PlaceCategoriesCompanion.insert(id: id, label: name, sort: Value(max.read<int>('m') + 1)));
    placeCategoryLabels[id] = name;
    return id;
  }

  /// The id of the category with this label (case does not matter), if any.
  Future<String?> idForLabel(String label) async {
    final rows = await (db.select(db.placeCategories)..where((c) => c.deletedAt.isNull())).get();
    final l = label.trim().toLowerCase();
    return rows.where((r) => r.label.toLowerCase() == l).firstOrNull?.id;
  }

  Future<void> rename(String id, String label) async {
    final name = label.trim();
    if (name.isEmpty) return;
    await (db.update(
      db.placeCategories,
    )..where((c) => c.id.equals(id))).write(PlaceCategoriesCompanion(label: Value(name)));
    placeCategoryLabels[id] = name;
    await _reindexPlaces(id);
  }

  /// New order, by id. "Other" always stays last.
  Future<void> reorder(List<String> ids) => db.transaction(() async {
    var i = 0;
    for (final id in ids) {
      if (id == PlaceCategory.other.name) continue;
      await (db.update(
        db.placeCategories,
      )..where((c) => c.id.equals(id))).write(PlaceCategoriesCompanion(sort: Value(i++)));
    }
  });

  /// How many live places use this category (for the delete confirmation).
  Future<int> placeCount(String id) async =>
      (await db
              .customSelect(
                "SELECT COUNT(*) AS n FROM people WHERE deleted_at IS NULL AND kind = 'place' AND place_category = ?",
                variables: [Variable.withString(id)],
              )
              .getSingle())
          .read<int>('n');

  /// Deletes a category; its places move to Other. Other itself can't go.
  Future<void> delete(String id) async {
    if (id == PlaceCategory.other.name) return;
    final moved = await _placeIds(id);
    await db.transaction(() async {
      await db.customUpdate(
        "UPDATE people SET place_category = '${PlaceCategory.other.name}' WHERE place_category = ?",
        variables: [Variable.withString(id)],
        updates: {db.people},
      );
      // A tombstone, not a delete, so sync can carry it to the other device.
      final t = DateTime.now();
      await (db.update(
        db.placeCategories,
      )..where((c) => c.id.equals(id))).write(PlaceCategoriesCompanion(deletedAt: Value(t), updatedAt: Value(t)));
    });
    placeCategoryLabels.remove(id);
    for (final p in moved) {
      await reindex?.call(p);
    }
  }

  Future<List<String>> _placeIds(String id) async => [
    for (final r
        in await db
            .customSelect(
              "SELECT uuid FROM people WHERE deleted_at IS NULL AND kind = 'place' AND place_category = ?",
              variables: [Variable.withString(id)],
            )
            .get())
      r.read<String>('uuid'),
  ];

  Future<void> _reindexPlaces(String id) async {
    for (final p in await _placeIds(id)) {
      await reindex?.call(p);
    }
  }
}
