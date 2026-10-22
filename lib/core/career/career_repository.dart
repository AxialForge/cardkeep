import 'dart:convert';

import 'package:drift/drift.dart';

import '../contacts/contacts_repository.dart';
import '../db/database.dart';
import '../dupes/duplicates_repository.dart';

/// A pending "this person may have changed jobs / retired" item (S12.1).
class CareerSuggestion {
  final String id, personId, personName;
  final SuggestionKind kind;
  final SuggestionSource source;
  final Map<String, Object?> payload; // newPersonId, company, title, email
  final DateTime createdAt;
  const CareerSuggestion(this.id, this.personId, this.personName, this.kind, this.source, this.payload, this.createdAt);

  String? get newPersonId => payload['newPersonId'] as String?;
  String? get newCompany => payload['company'] as String?;
  String? get newTitle => payload['title'] as String?;
}

/// How a possible job change is answered (S12.3).
enum JobChange {
  /// New current role; the old one stays as history, old work emails become former.
  keepHistory,

  /// The old company details are wrong or no longer wanted: replaced outright.
  replace,

  /// Not the same person: nothing changes and the pair isn't suggested again.
  different,
}

class PersonRef {
  final String id, name;
  final String? company, phone, email;
  const PersonRef(this.id, this.name, {this.company, this.phone, this.email});
}

/// Who replaced this person, and whom they replaced (S12.6, S12.7, S12.12).
class SuccessionView {
  final PersonRef? replacedBy;
  final String? replacedByRole;
  final List<PersonRef> replaces;
  const SuccessionView(this.replacedBy, this.replacedByRole, this.replaces);
}

/// Career tracking (roadmap S12): suggestions, job changes, retirement and
/// successions. Every write goes through ContactsRepository/DuplicatesRepository
/// helpers so search and tombstones stay right.
class CareerRepository {
  final AppDatabase db;
  final ContactsRepository contacts;
  final DuplicatesRepository dupes;
  final DateTime Function() now;

  CareerRepository(this.db, this.contacts, this.dupes, {DateTime Function()? clock}) : now = clock ?? DateTime.now;

  // --------------------------------------------------------------- reads

  Stream<List<CareerSuggestion>> watchPending({String? personId}) => db
      .customSelect(
        '''
SELECT s.uuid, s.person_id, s.kind, s.source, s.payload_json, s.created_at, p.display_name
FROM change_suggestions s JOIN people p ON p.uuid = s.person_id
WHERE s.status = 'pending' AND s.deleted_at IS NULL AND p.deleted_at IS NULL ${personId == null ? '' : 'AND s.person_id = ?'}
ORDER BY s.created_at DESC''',
        variables: [if (personId != null) Variable.withString(personId)],
        readsFrom: {db.changeSuggestions, db.people},
      )
      .watch()
      .map(
        (rows) => [
          for (final r in rows)
            CareerSuggestion(
              r.read('uuid'),
              r.read('person_id'),
              r.read('display_name'),
              SuggestionKind.values.byName(r.read('kind')),
              SuggestionSource.values.byName(r.read('source')),
              (jsonDecode(r.read<String>('payload_json')) as Map).cast<String, Object?>(),
              DateTime.fromMillisecondsSinceEpoch(r.read<int>('created_at') * 1000),
            ),
        ],
      );

  /// People who moved, retired or were replaced lately, newest first (S12.2).
  Stream<List<(PersonRef, PersonStatus, DateTime)>> watchRecent({int days = 180}) {
    final since = now().subtract(Duration(days: days));
    return db
        .customSelect(
          '''
SELECT p.uuid, p.display_name, p.status, p.updated_at FROM people p
WHERE p.deleted_at IS NULL AND p.status IN ('moved', 'retired') AND p.updated_at >= ?
ORDER BY p.updated_at DESC''',
          variables: [Variable.withDateTime(since)],
          readsFrom: {db.people},
        )
        .watch()
        .map(
          (rows) => [
            for (final r in rows)
              (
                PersonRef(r.read('uuid'), r.read('display_name')),
                PersonStatus.values.byName(r.read('status')),
                DateTime.fromMillisecondsSinceEpoch(r.read<int>('updated_at') * 1000),
              ),
          ],
        );
  }

  Stream<SuccessionView> watchSuccession(String personId) => db
      .customSelect('SELECT 1', readsFrom: {db.successions, db.people, db.contactPoints})
      .watch()
      .asyncMap((_) => succession(personId));

  Future<SuccessionView> succession(String personId) async {
    // Latest successor wins when there are several rows (S12.12).
    final next = await db
        .customSelect(
          '''
SELECT s.successor_person_id AS id, s.role_title FROM successions s
JOIN people p ON p.uuid = s.successor_person_id
WHERE s.predecessor_person_id = ? AND s.deleted_at IS NULL AND p.deleted_at IS NULL
ORDER BY COALESCE(s.effective_date, s.created_at) DESC LIMIT 1''',
          variables: [Variable.withString(personId)],
        )
        .getSingleOrNull();
    final prev = await db
        .customSelect(
          '''
SELECT DISTINCT s.predecessor_person_id AS id FROM successions s
JOIN people p ON p.uuid = s.predecessor_person_id
WHERE s.successor_person_id = ? AND s.deleted_at IS NULL AND p.deleted_at IS NULL''',
          variables: [Variable.withString(personId)],
        )
        .get();
    return SuccessionView(
      next == null ? null : await _ref(next.read<String>('id')),
      next?.readNullable<String>('role_title'),
      [for (final r in prev) ?await _ref(r.read<String>('id'))],
    );
  }

  // ----------------------------------------------------------- suggestions

  /// Off when Settings switches career tracking off for everyone (S12.10).
  Future<bool> _globalOn() async =>
      (await (db.select(db.appSettings)..where((s) => s.key.equals('track_career'))).getSingleOrNull())?.value !=
      'false';

  Future<bool> _tracks(String personId) async {
    final p = await (db.select(db.people)..where((x) => x.uuid.equals(personId))).getSingleOrNull();
    return p != null && p.trackCareer && await _globalOn();
  }

  /// A new card looks like [personId] at another company (S12.1 "scan").
  Future<String?> suggestMove(String personId, {String? newPersonId, String? company, String? title}) async {
    if (!await _tracks(personId)) return null;
    final open = await watchPending(personId: personId).first;
    if (open.any((s) => s.kind == SuggestionKind.moved && s.newPersonId == newPersonId && newPersonId != null)) {
      return null;
    }
    return _suggest(personId, SuggestionKind.moved, SuggestionSource.scan, {
      'newPersonId': ?newPersonId,
      'company': ?company,
      'title': ?title,
    });
  }

  /// After a scanned card is saved as [newPersonId]: anyone it matches at a
  /// different company gets a "possible job change" (S12.1). Returns how many.
  Future<int> checkNewCard(String newPersonId) async {
    var n = 0;
    for (final m in await dupes.matchesFor(newPersonId)) {
      if (m.match.sameCompany) continue;
      final id = await suggestMove(m.b.id, newPersonId: newPersonId, company: m.a.company);
      if (id != null) n++;
    }
    return n;
  }

  /// An email came back undeliverable (S12.1 "bounce"): the address is marked
  /// bounced (never a default target again, S12.11) and the person flagged.
  Future<void> markBounced(String pointId) async {
    final pt = await (db.select(db.contactPoints)..where((c) => c.uuid.equals(pointId))).getSingle();
    final t = now();
    await (db.update(db.contactPoints)..where((c) => c.uuid.equals(pointId))).write(
      ContactPointsCompanion(
        status: const Value(ContactStatus.bounced),
        isPrimary: const Value(false),
        updatedAt: Value(t),
      ),
    );
    if (await _tracks(pt.personId)) {
      await _suggest(pt.personId, SuggestionKind.bounce, SuggestionSource.bounce, {'email': pt.value});
    }
  }

  Future<String> _suggest(
    String personId,
    SuggestionKind kind,
    SuggestionSource source,
    Map<String, Object?> payload,
  ) async {
    final t = now();
    final id = uuidGen.v4();
    await db
        .into(db.changeSuggestions)
        .insert(
          ChangeSuggestionsCompanion.insert(
            uuid: Value(id),
            personId: personId,
            kind: kind,
            source: source,
            payloadJson: Value(jsonEncode(payload)),
            createdAt: Value(t),
            updatedAt: Value(t),
          ),
        );
    return id;
  }

  Future<void> dismiss(String suggestionId) => _status(suggestionId, SuggestionStatus.dismissed);

  Future<void> _status(String id, SuggestionStatus s) => (db.update(
    db.changeSuggestions,
  )..where((x) => x.uuid.equals(id))).write(ChangeSuggestionsCompanion(status: Value(s), updatedAt: Value(now())));

  // --------------------------------------------------------------- resolve

  /// Answers a possible job change (S12.3). For a scan suggestion the new
  /// card's record is merged into the person; otherwise [company]/[title]
  /// (or the suggestion's) become the new role. [successorId] records who
  /// took over the old job.
  Future<void> resolveMove(
    CareerSuggestion s,
    JobChange choice, {
    String? company,
    String? title,
    String? successorId,
  }) => db.transaction(() async {
    if (choice == JobChange.different) {
      if (s.newPersonId != null) await dupes.dismiss(s.personId, s.newPersonId!);
      await dismiss(s.id);
      return;
    }
    final before = await _currentRole(s.personId);
    final oldDomains = await _workDomains(s.personId);
    await changeJob(
      s.personId,
      newPersonId: s.newPersonId,
      company: company ?? s.newCompany,
      title: title ?? s.newTitle,
      replace: choice == JobChange.replace,
      oldDomains: oldDomains,
    );
    if (successorId != null && before != null) {
      await addSuccession(s.personId, successorId, companyId: before.companyId, roleTitle: before.title);
    }
    await _status(s.id, SuggestionStatus.applied);
  });

  /// Records a new job for [personId] (also the manual "Mark as moved").
  Future<void> changeJob(
    String personId, {
    String? newPersonId,
    String? company,
    String? title,
    bool replace = false,
    Set<String>? oldDomains,
  }) async {
    final t = now();
    oldDomains ??= await _workDomains(personId);
    final old = await _currentRole(personId);
    if (newPersonId != null) {
      // The new card's details win for the role; phones, emails and cards are combined.
      await dupes.merge(personId, newPersonId, const MergeChoices(role: Side.lose));
    } else if (company != null || title != null) {
      if (old != null) {
        await (db.update(db.roles)..where((r) => r.uuid.equals(old.uuid))).write(
          RolesCompanion(status: const Value(RoleStatus.former), endDate: Value(t), updatedAt: Value(t)),
        );
      }
      final cid = company == null ? null : await contacts.companyId(company, t);
      await db
          .into(db.roles)
          .insert(
            RolesCompanion.insert(
              personId: personId,
              companyId: Value(cid),
              title: Value(title ?? ''),
              startDate: Value(t),
              source: const Value(RoleSource.manual),
              confirmedAt: Value(t),
              createdAt: Value(t),
              updatedAt: Value(t),
            ),
          );
    }
    // Old work emails: kept as former history, or removed when replacing.
    final newDomains = await _workDomains(personId, activeOnly: true, excludeDomains: oldDomains);
    for (final pt
        in await (db.select(
              db.contactPoints,
            )..where((c) => c.personId.equals(personId) & c.kind.equalsValue(ContactKind.email) & c.deletedAt.isNull()))
            .get()) {
      final domain = pt.value.split('@').last.toLowerCase();
      if (!oldDomains.contains(domain) || newDomains.contains(domain)) continue;
      await (db.update(db.contactPoints)..where((c) => c.uuid.equals(pt.uuid))).write(
        replace
            ? ContactPointsCompanion(deletedAt: Value(t), updatedAt: Value(t))
            : ContactPointsCompanion(
                status: const Value(ContactStatus.former),
                isPrimary: const Value(false),
                updatedAt: Value(t),
              ),
      );
    }
    if (replace) {
      for (final r
          in await (db.select(db.roles)..where(
                (r) => r.personId.equals(personId) & r.status.equalsValue(RoleStatus.former) & r.deletedAt.isNull(),
              ))
              .get()) {
        if (old != null && r.uuid == old.uuid) {
          await (db.update(
            db.roles,
          )..where((x) => x.uuid.equals(r.uuid))).write(RolesCompanion(deletedAt: Value(t), updatedAt: Value(t)));
        }
      }
    }
    await (db.update(db.people)..where((p) => p.uuid.equals(personId))).write(
      PeopleCompanion(status: Value(replace ? PersonStatus.active : PersonStatus.moved), updatedAt: Value(t)),
    );
    await contacts.reindex(personId);
  }

  /// S12.5: current role and person marked retired; optional successor.
  Future<void> retire(String personId, {String? successorId, String note = ''}) => db.transaction(() async {
    final t = now();
    final role = await _currentRole(personId);
    if (role != null) {
      await (db.update(db.roles)..where((r) => r.uuid.equals(role.uuid))).write(
        RolesCompanion(status: const Value(RoleStatus.retired), endDate: Value(t), updatedAt: Value(t)),
      );
    }
    await (db.update(db.people)..where((p) => p.uuid.equals(personId))).write(
      PeopleCompanion(status: const Value(PersonStatus.retired), updatedAt: Value(t)),
    );
    if (successorId != null) {
      await addSuccession(personId, successorId, companyId: role?.companyId, roleTitle: role?.title ?? '', note: note);
    }
    for (final s in await watchPending(personId: personId).first) {
      await _status(s.id, SuggestionStatus.applied);
    }
    await contacts.reindex(personId);
  });

  /// Undo for "retired" (mistakes happen): role back to current, person active.
  Future<void> unretire(String personId) async {
    final t = now();
    final r =
        await (db.select(db.roles)
              ..where(
                (r) => r.personId.equals(personId) & r.status.equalsValue(RoleStatus.retired) & r.deletedAt.isNull(),
              )
              ..orderBy([(r) => OrderingTerm.desc(r.updatedAt)])
              ..limit(1))
            .getSingleOrNull();
    if (r != null) {
      await (db.update(db.roles)..where((x) => x.uuid.equals(r.uuid))).write(
        RolesCompanion(status: const Value(RoleStatus.current), endDate: const Value(null), updatedAt: Value(t)),
      );
    }
    await (db.update(db.people)..where((p) => p.uuid.equals(personId))).write(
      PeopleCompanion(status: const Value(PersonStatus.active), updatedAt: Value(t)),
    );
  }

  /// S12.6: one row per succession; the newest is shown (S12.12).
  Future<void> addSuccession(
    String predecessorId,
    String successorId, {
    String? companyId,
    String roleTitle = '',
    String note = '',
    String source = 'manual',
  }) async {
    final t = now();
    await db
        .into(db.successions)
        .insert(
          SuccessionsCompanion.insert(
            predecessorPersonId: predecessorId,
            successorPersonId: Value(successorId),
            companyId: Value(companyId),
            roleTitle: Value(roleTitle),
            effectiveDate: Value(t),
            source: Value(source),
            note: Value(note),
            createdAt: Value(t),
            updatedAt: Value(t),
          ),
        );
  }

  /// S12.8: the predecessor's open follow-up moves to the successor.
  Future<void> moveFollowup(String fromId, String toId) => db.transaction(() async {
    final from = await (db.select(db.people)..where((p) => p.uuid.equals(fromId))).getSingle();
    if (from.followupAt == null || from.followupDoneAt != null) return;
    final t = now();
    await (db.update(db.people)..where((p) => p.uuid.equals(toId))).write(
      PeopleCompanion(followupAt: Value(from.followupAt), followupDoneAt: const Value(null), updatedAt: Value(t)),
    );
    await (db.update(db.people)..where((p) => p.uuid.equals(fromId))).write(
      PeopleCompanion(followupAt: const Value(null), followupDoneAt: const Value(null), updatedAt: Value(t)),
    );
  });

  // -------------------------------------------------------------- helpers

  Future<Role?> _currentRole(String personId) =>
      (db.select(db.roles)
            ..where(
              (r) => r.personId.equals(personId) & r.status.equalsValue(RoleStatus.current) & r.deletedAt.isNull(),
            )
            ..orderBy([(r) => OrderingTerm.desc(r.updatedAt)])
            ..limit(1))
          .getSingleOrNull();

  static const _freeMail = {
    'gmail.com',
    'yahoo.com',
    'hotmail.com',
    'outlook.com',
    'icloud.com',
    'aol.com',
    'live.com',
  };

  Future<Set<String>> _workDomains(
    String personId, {
    bool activeOnly = false,
    Set<String> excludeDomains = const {},
  }) async {
    final rows = await (db.select(
      db.contactPoints,
    )..where((c) => c.personId.equals(personId) & c.kind.equalsValue(ContactKind.email) & c.deletedAt.isNull())).get();
    return {
      for (final r in rows)
        if (!activeOnly || r.status == ContactStatus.active)
          if (r.value.split('@').last.toLowerCase() case final d
              when !_freeMail.contains(d) && !excludeDomains.contains(d))
            d,
    };
  }

  Future<PersonRef?> _ref(String id) async {
    final d = await contacts.loadDetail(id);
    if (d == null) return null;
    return PersonRef(
      id,
      d.person.displayName,
      company: d.currentRole?.company,
      phone: d.callTarget?.value,
      email: d.emailTarget?.value,
    );
  }
}
