import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/plural.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/contacts/place_category_repository.dart';

/// Settings > Place categories (S14b.6): add, rename, reorder, delete.
/// "Other" stays last and can't be deleted; a deleted category's places move to it.
class PlaceCategoriesScreen extends ConsumerWidget {
  const PlaceCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(placeCategoryRepoProvider);
    final items = ref.watch(placeCategoriesProvider).value ?? const <PlaceCategoryItem>[];
    final movable = [
      for (final c in items)
        if (c.canDelete) c,
    ];
    final other = items.where((c) => !c.canDelete).toList();

    Future<void> add() async {
      final name = await askText(context, title: 'New category', action: 'Add');
      if (name != null) await repo.add(name);
    }

    Future<void> rename(PlaceCategoryItem c) async {
      final name = await askText(context, title: 'Rename category', action: 'Rename', initial: c.label);
      if (name != null) await repo.rename(c.id, name);
    }

    Future<void> delete(PlaceCategoryItem c) async {
      final n = await repo.placeCount(c.id);
      if (!context.mounted) return;
      final ok = await confirm(
        context,
        title: 'Delete ${c.label}?',
        message: n == 0 ? 'No places use it.' : '${plural(n, 'place')} will move to Other.',
        action: 'Delete',
        destructive: true,
      );
      if (ok) await repo.delete(c.id);
    }

    Widget tile(PlaceCategoryItem c, {Key? key, int? index}) => ListTile(
      key: key,
      title: Text(c.label, style: AppText.body),
      subtitle: c.canDelete ? null : Text('Places from a deleted category go here', style: AppText.secondary),
      onTap: () => rename(c),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(tooltip: 'Rename', icon: const Icon(Icons.edit_outlined), onPressed: () => rename(c)),
          if (c.canDelete)
            IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => delete(c)),
          if (index != null)
            ReorderableDragStartListener(
              index: index,
              child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle)),
            ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Place categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: add,
        icon: const Icon(Icons.add),
        label: const Text('New category'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Text('Drag to reorder. Tap a category to rename it.', style: AppText.secondary),
          ),
          Panel(
            padding: EdgeInsets.zero,
            child: ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (from, to) {
                final ids = [for (final c in movable) c.id];
                ids.insert(to, ids.removeAt(from));
                repo.reorder(ids);
              },
              children: [for (final (i, c) in movable.indexed) tile(c, key: ValueKey(c.id), index: i)],
            ),
          ),
          if (other.isNotEmpty) Panel(padding: EdgeInsets.zero, child: tile(other.single)),
        ],
      ),
    );
  }
}
