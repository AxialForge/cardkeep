import 'package:drift/drift.dart';

import '../contacts/contacts_repository.dart';
import '../db/database.dart';

/// Tag colours (hex, stored as text). Picked to read on light and dark
/// grounds with white text.
const tagColorNames = ['Orange', 'Brass', 'Green', 'Blue', 'Purple', 'Berry', 'Slate', 'Grey'];
const tagColors = ['#C4542D', '#B08A4A', '#2F7D4F', '#2C5D8F', '#6B4C9A', '#A33A5B', '#4F6B6B', '#6E6A60'];

/// Tags the app creates when needed (S9.4); renameable like any other.
enum SystemTag {
  imported('Imported', '#4F6B6B'),
  nfcLink('NFC link', '#2C5D8F'),
  demo('Demo', '#6E6A60');

  final String defaultName, color;
  const SystemTag(this.defaultName, this.color);
}

class TagView {
  final String id, name, color;
  final int count; // live people with this tag
  const TagView(this.id, this.name, this.color, this.count);
}

/// Your own groups (roadmap S9).
class TagsRepository {
  final AppDatabase db;
  final ContactsRepository contacts;
  final DateTime Function() now;

  TagsRepository(this.db, this.contacts, {DateTime Function()? clock}) : now = clock ?? DateTime.now;

  Stream<List<TagView>> watchTags() => db
      .customSelect(
        '''
SELECT t.uuid, t.name, t.color,
  (SELECT COUNT(*) FROM person_tags pt JOIN people p ON p.uuid = pt.person_id
     WHERE pt.tag_id = t.uuid AND pt.deleted_at IS NULL AND p.deleted_at IS NULL) AS n
FROM tags t WHERE t.deleted_at IS NULL ORDER BY t.name COLLATE NOCASE''',
        readsFrom: {db.tags, db.personTags, db.people},
      )
      .watch()
      .map((rows) => [for (final r in rows) TagView(r.read('uuid'), r.read('name'), r.read('color'), r.read('n'))]);

  /// One person's tags, by name.
  Stream<List<TagView>> watchTagsOf(String personId) => db
      .customSelect(
        '''
SELECT t.uuid, t.name, t.color FROM person_tags pt JOIN tags t ON t.uuid = pt.tag_id
WHERE pt.person_id = ? AND pt.deleted_at IS NULL AND t.deleted_at IS NULL ORDER BY t.name COLLATE NOCASE''',
        variables: [Variable.withString(personId)],
        readsFrom: {db.tags, db.personTags},
      )
      .watch()
      .map((rows) => [for (final r in rows) TagView(r.read('uuid'), r.read('name'), r.read('color'), 0)]);

  /// Creates a tag, or returns the live one with the same name (any case).
  Future<String> create(String name, {String? color}) async {
    final n = name.trim();
    final existing = await _byName(n);
    if (existing != null) return existing.uuid;
    final count = (await db.customSelect('SELECT COUNT(*) AS c FROM tags').getSingle()).read<int>('c');
    final t = now();
    final row = await db
        .into(db.tags)
        .insertReturning(
          TagsCompanion.insert(
            name: n,
            color: Value(color ?? tagColors[count % tagColors.length]),
            createdAt: Value(t),
            updatedAt: Value(t),
          ),
        );
    return row.uuid;
  }

  Future<String> ensureSystem(SystemTag s) async {
    final key = 'tag.system.${s.name}';
    final saved = await (db.select(db.appSettings)..where((a) => a.key.equals(key))).getSingleOrNull();
    if (saved != null) {
      final tag = await (db.select(
        db.tags,
      )..where((t) => t.uuid.equals(saved.value) & t.deletedAt.isNull())).getSingleOrNull();
      if (tag != null) return tag.uuid;
    }
    final id = await create(s.defaultName, color: s.color);
    await db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: id));
    return id;
  }

  Future<void> rename(String id, String name) async {
    await (db.update(
      db.tags,
    )..where((t) => t.uuid.equals(id))).write(TagsCompanion(name: Value(name.trim()), updatedAt: Value(now())));
    await _reindexTagged(id);
  }

  Future<void> recolor(String id, String color) => (db.update(
    db.tags,
  )..where((t) => t.uuid.equals(id))).write(TagsCompanion(color: Value(color), updatedAt: Value(now())));

  /// Tombstones the tag and its assignments; people keep everything else.
  Future<void> delete(String id) => db.transaction(() async {
    final people = await _peopleWith(id);
    final t = now();
    await (db.update(
      db.tags,
    )..where((x) => x.uuid.equals(id))).write(TagsCompanion(deletedAt: Value(t), updatedAt: Value(t)));
    await (db.update(db.personTags)..where((x) => x.tagId.equals(id) & x.deletedAt.isNull())).write(
      PersonTagsCompanion(deletedAt: Value(t), updatedAt: Value(t)),
    );
    for (final p in people) {
      await contacts.reindex(p);
    }
  });

  /// Sets exactly these tags on one person.
  Future<void> setTags(String personId, Set<String> tagIds) => db.transaction(() async {
    final current = await (db.select(db.personTags)..where((x) => x.personId.equals(personId))).get();
    final t = now();
    for (final row in current) {
      final want = tagIds.contains(row.tagId);
      final live = row.deletedAt == null;
      if (want != live) {
        await (db.update(db.personTags)..where((x) => x.uuid.equals(row.uuid))).write(
          PersonTagsCompanion(deletedAt: Value(want ? null : t), updatedAt: Value(t)),
        );
      }
    }
    final known = {for (final r in current) r.tagId};
    for (final id in tagIds.difference(known)) {
      await db
          .into(db.personTags)
          .insert(PersonTagsCompanion.insert(personId: personId, tagId: id, createdAt: Value(t), updatedAt: Value(t)));
    }
    await contacts.reindex(personId);
  });

  /// Adds one tag to many people (multi-select).
  Future<void> addToAll(Iterable<String> personIds, String tagId) => db.transaction(() async {
    for (final p in personIds) {
      final have = await (db.select(db.personTags)..where((x) => x.personId.equals(p))).get();
      await setTags(p, {for (final r in have.where((r) => r.deletedAt == null)) r.tagId, tagId});
    }
  });

  Future<Tag?> _byName(String name) =>
      (db.select(db.tags)
            ..where((t) => t.name.lower().equals(name.toLowerCase()) & t.deletedAt.isNull())
            ..limit(1))
          .getSingleOrNull();

  Future<List<String>> _peopleWith(String tagId) async => [
    for (final r in await (db.select(db.personTags)..where((x) => x.tagId.equals(tagId) & x.deletedAt.isNull())).get())
      r.personId,
  ];

  Future<void> _reindexTagged(String tagId) async {
    for (final p in await _peopleWith(tagId)) {
      await contacts.reindex(p);
    }
  }
}
