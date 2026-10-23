import 'package:drift/drift.dart';

import '../contacts/contacts_repository.dart';
import '../db/database.dart';
import 'matcher.dart';

/// Which record a merged field comes from.
enum Side { keep, lose }

/// The per-field picks on the Merge screen. Contact points, tags, cards and
/// notes are always the union.
class MergeChoices {
  final Side name;
  final Side role; // title + company
  final Side rating;
  final Side followup;
  const MergeChoices({
    this.name = Side.keep,
    this.role = Side.keep,
    this.rating = Side.keep,
    this.followup = Side.keep,
  });
}

/// Everything a merge changed, so it can be undone until the app closes (S8.7).
class MergeUndo {
  final String keeperId, loserId;
  final PeopleData keeperBefore;
  final Map<String, List<String>> repointed; // table -> row uuids moved from loser
  final List<String> tombstonedPoints, tombstonedTags, tombstonedRoles;
  final Map<String, RoleStatus> roleStatus; // role uuid -> status before
  final Map<String, bool> pointPrimary; // point uuid -> isPrimary before
  final List<String> successionsPred, successionsSucc, introduced;

  MergeUndo({
    required this.keeperId,
    required this.loserId,
    required this.keeperBefore,
    required this.repointed,
    required this.tombstonedPoints,
    required this.tombstonedTags,
    required this.tombstonedRoles,
    required this.roleStatus,
    required this.pointPrimary,
    required this.successionsPred,
    required this.successionsSucc,
    required this.introduced,
  });
}

/// Finds and merges duplicate people (roadmap S8).
class DuplicatesRepository {
  final AppDatabase db;
  final ContactsRepository contacts;
  final DateTime Function() now;

  DuplicatesRepository(this.db, this.contacts, {DateTime Function()? clock}) : now = clock ?? DateTime.now;

  /// Every live person as a match candidate.
  Future<List<MatchCandidate>> candidates() async {
    final rows = await db.customSelect('''
SELECT p.uuid, p.display_name, p.kind,
  (SELECT c.name FROM roles r JOIN companies c ON c.uuid = r.company_id
     WHERE r.person_id = p.uuid AND r.status = 'current' AND r.deleted_at IS NULL
     ORDER BY r.updated_at DESC LIMIT 1) AS company,
  (SELECT group_concat(value, char(31)) FROM contact_points cp
     WHERE cp.person_id = p.uuid AND cp.deleted_at IS NULL AND cp.kind = 'mobile') AS mobiles,
  (SELECT group_concat(value, char(31)) FROM contact_points cp
     WHERE cp.person_id = p.uuid AND cp.deleted_at IS NULL AND cp.kind = 'email') AS emails,
  (SELECT group_concat(value, char(31)) FROM contact_points cp
     WHERE cp.person_id = p.uuid AND cp.deleted_at IS NULL AND cp.kind IN ('mobile', 'office')) AS phones,
  (SELECT value FROM contact_points cp
     WHERE cp.person_id = p.uuid AND cp.deleted_at IS NULL AND cp.kind = 'address' LIMIT 1) AS address
FROM people p WHERE p.deleted_at IS NULL''').get();
    Set<String> split(String? s) => s == null || s.isEmpty ? {} : s.split('\u001f').toSet();
    return [
      for (final r in rows)
        MatchCandidate(
          id: r.read<String>('uuid'),
          name: r.read<String>('display_name'),
          company: r.readNullable<String>('company') ?? '',
          mobiles: split(r.readNullable<String>('mobiles')),
          emails: {for (final e in split(r.readNullable<String>('emails'))) e.toLowerCase()},
          isPlace: r.read<String>('kind') == PersonKind.place.name,
          phones: split(r.readNullable<String>('phones')),
          address: r.readNullable<String>('address') ?? '',
        ),
    ];
  }

  Future<Set<String>> dismissed() async => {
    for (final r in await (db.select(db.notDuplicates)..where((n) => n.deletedAt.isNull())).get()) r.pairKey,
  };

  /// The whole library, best match first (S8.3).
  Future<List<DupPair>> scanAll() async => findPairs(await candidates(), dismissed: await dismissed());

  /// Matches for one person (shown on their detail screen).
  Future<List<DupPair>> matchesFor(String personId) async {
    final all = await candidates();
    final me = all.where((c) => c.id == personId).firstOrNull;
    if (me == null) return const [];
    final skip = await dismissed();
    return [
      for (final other in all)
        if (other.id != personId && !skip.contains(pairKey(personId, other.id)))
          if (matchPair(me, other) case final m?) DupPair(me, other, m),
    ]..sort((x, y) => y.match.score.compareTo(x.match.score));
  }

  /// "Not a duplicate": the pair never shows again (S8.6).
  Future<void> dismiss(String a, String b) async {
    final t = now();
    await db
        .into(db.notDuplicates)
        .insert(
          NotDuplicatesCompanion.insert(pairKey: pairKey(a, b), createdAt: Value(t), updatedAt: Value(t)),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// Merges [loserId] into [keeperId]: picks fields, unions the rest, repoints
  /// every reference and tombstones the loser (S8.4, S8.5).
  Future<MergeUndo> merge(String keeperId, String loserId, MergeChoices c) => db.transaction(() async {
    final t = now();
    final keeper = await _person(keeperId);
    final loser = await _person(loserId);

    // People fields.
    String pick(Side s, String k, String l) => s == Side.lose && l.isNotEmpty ? l : (k.isEmpty ? l : k);
    final notes = [keeper.notes, loser.notes].where((n) => n.trim().isNotEmpty).toSet().join('\n');
    await (db.update(db.people)..where((p) => p.uuid.equals(keeperId))).write(
      PeopleCompanion(
        first: Value(c.name == Side.lose ? loser.first : keeper.first),
        last: Value(c.name == Side.lose ? loser.last : keeper.last),
        displayName: Value(pick(c.name, keeper.displayName, loser.displayName)),
        leadRating: Value(
          c.rating == Side.lose ? loser.leadRating ?? keeper.leadRating : keeper.leadRating ?? loser.leadRating,
        ),
        followupAt: Value(
          c.followup == Side.lose ? loser.followupAt ?? keeper.followupAt : keeper.followupAt ?? loser.followupAt,
        ),
        followupDoneAt: Value(c.followup == Side.lose ? loser.followupDoneAt : keeper.followupDoneAt),
        notes: Value(notes),
        metEventId: Value(keeper.metEventId ?? loser.metEventId),
        introducedByPersonId: Value(keeper.introducedByPersonId ?? loser.introducedByPersonId),
        updatedAt: Value(t),
      ),
    );

    // Current roles: the picked one stays current; the other is dropped when it
    // is the same company, else kept as a former role (history).
    final roleStatus = <String, RoleStatus>{};
    final tombRoles = <String>[];
    final kRole = await _currentRole(keeperId), lRole = await _currentRole(loserId);
    if (kRole != null && lRole != null) {
      final drop = c.role == Side.lose ? kRole : lRole;
      if (kRole.companyId == lRole.companyId) {
        tombRoles.add(drop.uuid);
        await _tombstone('roles', drop.uuid, t);
      } else {
        roleStatus[drop.uuid] = drop.status;
        await (db.update(db.roles)..where((r) => r.uuid.equals(drop.uuid))).write(
          RolesCompanion(status: const Value(RoleStatus.former), endDate: Value(t), updatedAt: Value(t)),
        );
      }
    }

    // Contact points: loser's go to the keeper; exact repeats are dropped and
    // the keeper's primaries stay primary.
    final kPoints = await (db.select(
      db.contactPoints,
    )..where((p) => p.personId.equals(keeperId) & p.deletedAt.isNull())).get();
    final lPoints = await (db.select(
      db.contactPoints,
    )..where((p) => p.personId.equals(loserId) & p.deletedAt.isNull())).get();
    final tombPoints = <String>[];
    final primary = <String, bool>{};
    final movedPoints = <String>[];
    for (final p in lPoints) {
      if (kPoints.any((k) => k.kind == p.kind && k.value.toLowerCase() == p.value.toLowerCase())) {
        tombPoints.add(p.uuid);
        await _tombstone('contact_points', p.uuid, t);
      } else {
        movedPoints.add(p.uuid);
        primary[p.uuid] = p.isPrimary;
        final hasPrimary = kPoints.any((k) => k.kind == p.kind && k.isPrimary);
        await (db.update(db.contactPoints)..where((x) => x.uuid.equals(p.uuid))).write(
          ContactPointsCompanion(
            personId: Value(keeperId),
            isPrimary: Value(p.isPrimary && !hasPrimary),
            updatedAt: Value(t),
          ),
        );
      }
    }

    // Tags: union, without repeating a tag the keeper already has.
    final kTags = {
      for (final r in await (db.select(
        db.personTags,
      )..where((x) => x.personId.equals(keeperId) & x.deletedAt.isNull())).get())
        r.tagId,
    };
    final tombTags = <String>[];
    final movedTags = <String>[];
    for (final r in await (db.select(
      db.personTags,
    )..where((x) => x.personId.equals(loserId) & x.deletedAt.isNull())).get()) {
      if (kTags.contains(r.tagId)) {
        tombTags.add(r.uuid);
        await _tombstone('person_tags', r.uuid, t);
      } else {
        movedTags.add(r.uuid);
        await (db.update(db.personTags)..where((x) => x.uuid.equals(r.uuid))).write(
          PersonTagsCompanion(personId: Value(keeperId), updatedAt: Value(t)),
        );
      }
    }

    // Everything else that points at the loser.
    final movedRoles = await _repoint('roles', loserId, keeperId, t);
    final movedCards = await _repoint('cards', loserId, keeperId, t);
    final movedSugg = await _repoint('change_suggestions', loserId, keeperId, t);
    final pred = await _ids('successions', 'predecessor_person_id', loserId);
    final succ = await _ids('successions', 'successor_person_id', loserId);
    final intro = await _ids('people', 'introduced_by_person_id', loserId);
    await _set('successions', 'predecessor_person_id', pred, keeperId, t);
    await _set('successions', 'successor_person_id', succ, keeperId, t);
    await _set('people', 'introduced_by_person_id', intro.where((i) => i != keeperId).toList(), keeperId, t);

    await db.tombstonePerson(loserId);
    await db.customStatement('DELETE FROM person_search WHERE person_id = ?', [loserId]);
    await contacts.reindex(keeperId);

    return MergeUndo(
      keeperId: keeperId,
      loserId: loserId,
      keeperBefore: keeper,
      repointed: {
        'roles': movedRoles,
        'cards': movedCards,
        'change_suggestions': movedSugg,
        'contact_points': movedPoints,
        'person_tags': movedTags,
      },
      tombstonedPoints: tombPoints,
      tombstonedTags: tombTags,
      tombstonedRoles: tombRoles,
      roleStatus: roleStatus,
      pointPrimary: primary,
      successionsPred: pred,
      successionsSucc: succ,
      introduced: intro.where((i) => i != keeperId).toList(),
    );
  });

  /// Puts both people back exactly as they were (S8.7).
  Future<void> undo(MergeUndo u) => db.transaction(() async {
    final t = now();
    await db.update(db.people).replace(u.keeperBefore.copyWith(updatedAt: t));
    await (db.update(db.people)..where((p) => p.uuid.equals(u.loserId))).write(
      PeopleCompanion(deletedAt: const Value(null), updatedAt: Value(t)),
    );
    for (final MapEntry(key: table, value: ids) in u.repointed.entries) {
      await _set(table, 'person_id', ids, u.loserId, t);
    }
    for (final MapEntry(key: id, value: was) in u.pointPrimary.entries) {
      await (db.update(
        db.contactPoints,
      )..where((p) => p.uuid.equals(id))).write(ContactPointsCompanion(isPrimary: Value(was)));
    }
    for (final MapEntry(key: id, value: was) in u.roleStatus.entries) {
      await (db.update(db.roles)..where((r) => r.uuid.equals(id))).write(
        RolesCompanion(status: Value(was), endDate: const Value(null), updatedAt: Value(t)),
      );
    }
    await _untombstone('contact_points', u.tombstonedPoints, t);
    await _untombstone('person_tags', u.tombstonedTags, t);
    await _untombstone('roles', u.tombstonedRoles, t);
    await _set('successions', 'predecessor_person_id', u.successionsPred, u.loserId, t);
    await _set('successions', 'successor_person_id', u.successionsSucc, u.loserId, t);
    await _set('people', 'introduced_by_person_id', u.introduced, u.loserId, t);
    await contacts.reindex(u.keeperId);
    await contacts.reindex(u.loserId);
  });

  // -------------------------------------------------------------- helpers

  Future<PeopleData> _person(String id) => (db.select(db.people)..where((p) => p.uuid.equals(id))).getSingle();

  Future<Role?> _currentRole(String personId) =>
      (db.select(db.roles)
            ..where(
              (r) => r.personId.equals(personId) & r.status.equalsValue(RoleStatus.current) & r.deletedAt.isNull(),
            )
            ..orderBy([(r) => OrderingTerm.desc(r.updatedAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<void> _tombstone(String table, String uuid, DateTime t) =>
      db.customStatement('UPDATE $table SET deleted_at = ?, updated_at = ? WHERE uuid = ?', [_secs(t), _secs(t), uuid]);

  Future<void> _untombstone(String table, List<String> ids, DateTime t) async {
    for (final id in ids) {
      await db.customStatement('UPDATE $table SET deleted_at = NULL, updated_at = ? WHERE uuid = ?', [_secs(t), id]);
    }
  }

  Future<List<String>> _repoint(String name, String from, String to, DateTime t) async {
    final ids = await _ids(name, 'person_id', from);
    await _set(name, 'person_id', ids, to, t);
    return ids;
  }

  Future<List<String>> _ids(String table, String column, String value) async => [
    for (final r
        in await db
            .customSelect('SELECT uuid FROM $table WHERE $column = ?', variables: [Variable.withString(value)])
            .get())
      r.read<String>('uuid'),
  ];

  Future<void> _set(String table, String column, List<String> ids, String value, DateTime t) async {
    for (final id in ids) {
      await db.customStatement('UPDATE $table SET $column = ?, updated_at = ? WHERE uuid = ?', [value, _secs(t), id]);
    }
  }

  static int _secs(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
}
