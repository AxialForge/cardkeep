import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/drawer.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/tags/tags_repository.dart';

final tagsRepoProvider = Provider(
  (ref) => TagsRepository(ref.watch(databaseProvider), ref.watch(contactsRepoProvider)),
);
final tagsProvider = StreamProvider<List<TagView>>((ref) => ref.watch(tagsRepoProvider).watchTags());
final tagsOfProvider = StreamProvider.family<List<TagView>, String>(
  (ref, id) => ref.watch(tagsRepoProvider).watchTagsOf(id),
);

Color tagColor(String hex) => Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));

/// A small coloured tag label.
class TagChip extends StatelessWidget {
  final TagView tag;
  final VoidCallback? onTap;
  const TagChip(this.tag, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: tagColor(tag.color),
    borderRadius: BorderRadius.circular(99),
    child: InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(tag.name, style: AppText.label.copyWith(color: Colors.white)),
      ),
    ),
  );
}

/// Tags (mockup Tags): create, rename, recolour, delete (S9.1).
class TagsScreen extends ConsumerWidget {
  const TagsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagsProvider).value ?? const <TagView>[];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Tokens.groundOverlay,
      child: Scaffold(
        drawer: const AppDrawer(current: '/tags'),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => editTag(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('New tag'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Tokens.gutter, 8, Tokens.gutter, 0),
                child: Row(
                  children: [
                    Builder(
                      builder: (c) => DiscButton(
                        icon: Icons.short_text,
                        tooltip: 'Menu',
                        onPressed: () => Scaffold.of(c).openDrawer(),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                child: Text('Tags', style: AppText.display),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Your own groups: customers, suppliers, a trade show, people to call back. Tap a tag to see who has it.',
                  style: AppText.secondary,
                ),
              ),
              if (tags.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: EmptyState(
                    icon: Icons.sell_outlined,
                    title: 'No tags yet',
                    message: 'Make one here, or add tags from a contact\'s page.',
                  ),
                ),
              if (tags.isNotEmpty)
                Panel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final t in tags)
                        ListTile(
                          leading: CircleAvatar(radius: 10, backgroundColor: tagColor(t.color)),
                          title: Text(t.name, style: AppText.bodyStrong),
                          subtitle: Text('${t.count} ${t.count == 1 ? 'person' : 'people'}', style: AppText.secondary),
                          trailing: IconButton(
                            tooltip: 'Edit ${t.name}',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => editTag(context, ref, tag: t),
                          ),
                          onTap: () {
                            ref.read(contactFilterProvider.notifier).update((f) => f.copyWith(tagId: () => t.id));
                            context.go('/');
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// New tag, or edit one (name, colour, delete). Returns the tag id when saved.
Future<String?> editTag(BuildContext context, WidgetRef ref, {TagView? tag}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _TagSheet(tag: tag),
);

class _TagSheet extends ConsumerStatefulWidget {
  final TagView? tag;
  const _TagSheet({this.tag});

  @override
  ConsumerState<_TagSheet> createState() => _TagSheetState();
}

class _TagSheetState extends ConsumerState<_TagSheet> {
  late final _name = TextEditingController(text: widget.tag?.name ?? '');
  late String? _color = widget.tag?.color;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final repo = ref.read(tagsRepoProvider);
    final t = widget.tag;
    String id;
    if (t == null) {
      id = await repo.create(name, color: _color);
    } else {
      id = t.id;
      if (name != t.name) await repo.rename(id, name);
      if (_color != null && _color != t.color) await repo.recolor(id, _color!);
    }
    if (mounted) Navigator.pop(context, id);
  }

  Future<void> _delete() async {
    final t = widget.tag!;
    final ok = await confirm(
      context,
      title: 'Delete "${t.name}"?',
      message: t.count == 0
          ? 'No one has this tag.'
          : 'It is removed from ${t.count} ${t.count == 1 ? 'person' : 'people'}. The contacts themselves stay.',
      action: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(tagsRepoProvider).delete(t.id);
    final f = ref.read(contactFilterProvider);
    if (f.tagId == t.id) ref.read(contactFilterProvider.notifier).update((f) => f.copyWith(tagId: () => null));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.tag == null ? 'New tag' : 'Edit tag', style: AppText.heading),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          autofocus: widget.tag == null,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 14),
        Text('Colour', style: AppText.label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in tagColors)
              Semantics(
                button: true,
                selected: (_color ?? widget.tag?.color) == c,
                label: '${tagColorNames[tagColors.indexOf(c)]} colour',
                child: GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tagColor(c),
                      shape: BoxShape.circle,
                      border: Border.all(color: _color == c ? Tokens.ink : Colors.transparent, width: 3),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        FilledButton(onPressed: _save, child: const Text('Save')),
        if (widget.tag != null)
          TextButton.icon(
            onPressed: _delete,
            icon: Icon(Icons.delete_outline, color: Tokens.hotFg),
            label: Text('Delete tag', style: TextStyle(color: Tokens.hotFg)),
          ),
      ],
    ),
  );
}

/// Pick tags (checkboxes) with a "New tag" row. Returns the chosen ids, or
/// null when cancelled.
Future<Set<String>?> pickTags(BuildContext context, {required Set<String> initial, String title = 'Tags'}) =>
    showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TagPicker(initial: initial, title: title),
    );

class _TagPicker extends ConsumerStatefulWidget {
  final Set<String> initial;
  final String title;
  const _TagPicker({required this.initial, required this.title});

  @override
  ConsumerState<_TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends ConsumerState<_TagPicker> {
  late final Set<String> _on = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(tagsProvider).value ?? const <TagView>[];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(widget.title, style: AppText.heading),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final t in tags)
                    CheckboxListTile(
                      value: _on.contains(t.id),
                      onChanged: (v) => setState(() => v! ? _on.add(t.id) : _on.remove(t.id)),
                      secondary: CircleAvatar(radius: 9, backgroundColor: tagColor(t.color)),
                      title: Text(t.name, style: AppText.body),
                    ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('New tag'),
                    onTap: () async {
                      final id = await editTag(context, ref);
                      if (id != null) setState(() => _on.add(id));
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton(onPressed: () => Navigator.pop(context, _on), child: const Text('Done')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tags on a contact's page, with Edit (S9.2).
class ContactTagsPanel extends ConsumerWidget {
  final String personId;
  const ContactTagsPanel({super.key, required this.personId});

  Future<void> _edit(BuildContext context, WidgetRef ref, List<TagView> mine) async {
    final picked = await pickTags(context, initial: {for (final t in mine) t.id});
    if (picked != null) await ref.read(tagsRepoProvider).setTags(personId, picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(tagsOfProvider(personId)).value ?? const <TagView>[];
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Tags', style: AppText.secondary)),
              TextButton(onPressed: () => _edit(context, ref, mine), child: Text(mine.isEmpty ? 'Add' : 'Edit')),
            ],
          ),
          if (mine.isEmpty)
            Text('None yet', style: AppText.body)
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in mine)
                  TagChip(
                    t,
                    onTap: () {
                      ref.read(contactFilterProvider.notifier).update((f) => f.copyWith(tagId: () => t.id));
                      context.go('/');
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
