import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import '../db/database.dart';
import '../text/normalize.dart';
import '../vcard/vcard.dart';
import 'contact_models.dart';

/// The only writer of people, companies, roles and contact points.
/// Keeps updated_at, tombstones and the search index right so the UI never has to.
class ContactsRepository {
  final AppDatabase db;
  final DateTime Function() now;

  ContactsRepository(this.db, {DateTime Function()? clock}) : now = clock ?? DateTime.now;

  // ---------------------------------------------------------------- reads

  Stream<List<ContactSummary>> watchContacts(ContactFilter f, {bool byFirst = false}) {
    final where = <String>['p.deleted_at IS NULL'];
    final vars = <Variable<Object>>[];
    final match = ftsQuery(f.query);
    if (match != null) {
      where.add('p.uuid IN (SELECT person_id FROM person_search WHERE person_search MATCH ?)');
      vars.add(Variable.withString(match));
    }
    if (f.rating != null) {
      where.add('p.lead_rating = ?');
      vars.add(Variable.withString(f.rating!.name));
    }
    if (f.status != null) {
      where.add('p.status = ?');
      vars.add(Variable.withString(f.status!.name));
    }
    if (f.followupOnly) where.add('p.followup_at IS NOT NULL AND p.followup_done_at IS NULL');
    if (f.tagId != null) {
      where.add('p.uuid IN (SELECT person_id FROM person_tags WHERE tag_id = ? AND deleted_at IS NULL)');
      vars.add(Variable.withString(f.tagId!));
    }

    final order = switch (f.sort) {
      ContactSort.name when byFirst =>
        "COALESCE(NULLIF(p.first, ''), p.display_name) COLLATE NOCASE, p.last COLLATE NOCASE",
      ContactSort.name => "COALESCE(NULLIF(p.last, ''), p.display_name) COLLATE NOCASE, p.first COLLATE NOCASE",
      ContactSort.company => "c.name IS NULL, c.name COLLATE NOCASE, p.last COLLATE NOCASE, p.first COLLATE NOCASE",
      ContactSort.recent => 'p.created_at DESC',
    };

    final sql =
        '''
SELECT p.uuid, p.first, p.last, p.display_name, p.lead_rating, p.status, p.followup_at, p.created_at,
       r.title AS title, c.name AS company
FROM people p
LEFT JOIN roles r ON r.uuid = (
  SELECT r2.uuid FROM roles r2
  WHERE r2.person_id = p.uuid AND r2.status = 'current' AND r2.deleted_at IS NULL
  ORDER BY r2.updated_at DESC LIMIT 1)
LEFT JOIN companies c ON c.uuid = r.company_id
WHERE ${where.join(' AND ')}
ORDER BY $order''';

    return db
        .customSelect(
          sql,
          variables: vars,
          readsFrom: {db.people, db.roles, db.companies, db.contactPoints, db.personTags},
        )
        .watch()
        .map(
          (rows) => [
            for (final r in rows)
              ContactSummary(
                id: r.read<String>('uuid'),
                first: r.read<String>('first'),
                last: r.read<String>('last'),
                displayName: r.read<String>('display_name'),
                title: r.readNullable<String>('title'),
                company: r.readNullable<String>('company'),
                leadRating: _enum(LeadRating.values, r.readNullable<String>('lead_rating')),
                status: _enum(PersonStatus.values, r.read<String>('status')) ?? PersonStatus.active,
                followupAt: _date(r.readNullable<int>('followup_at')),
                createdAt: _date(r.read<int>('created_at'))!,
              ),
          ],
        );
  }

  Stream<LibraryStats> watchStats() {
    final weekEnd = now().add(const Duration(days: 7));
    return db
        .customSelect(
          '''
SELECT
  (SELECT COUNT(*) FROM people WHERE deleted_at IS NULL) AS people,
  (SELECT COUNT(DISTINCT r.company_id) FROM roles r JOIN people p ON p.uuid = r.person_id
     WHERE r.status = 'current' AND r.deleted_at IS NULL AND p.deleted_at IS NULL AND r.company_id IS NOT NULL) AS companies,
  (SELECT COUNT(*) FROM people WHERE deleted_at IS NULL AND followup_at IS NOT NULL
     AND followup_done_at IS NULL AND followup_at <= ?) AS due''',
          variables: [Variable.withDateTime(weekEnd)],
          readsFrom: {db.people, db.roles},
        )
        .watch()
        .map((rows) {
          final r = rows.single;
          return LibraryStats(r.read<int>('people'), r.read<int>('companies'), r.read<int>('due'));
        });
  }

  Stream<ContactDetail?> watchDetail(String id) => db
      .customSelect('SELECT 1', readsFrom: {db.people, db.roles, db.companies, db.contactPoints, db.cards})
      .watch()
      .asyncMap((_) => loadDetail(id));

  Future<ContactDetail?> loadDetail(String id) async {
    final person = await (db.select(db.people)..where((p) => p.uuid.equals(id))).getSingleOrNull();
    if (person == null || person.deletedAt != null) return null;

    final roleRows = await (db.select(db.roles).join([
      leftOuterJoin(db.companies, db.companies.uuid.equalsExp(db.roles.companyId)),
    ])..where(db.roles.personId.equals(id) & db.roles.deletedAt.isNull())).get();
    final roles =
        [
          for (final row in roleRows)
            RoleView(
              row.readTable(db.roles).uuid,
              row.readTable(db.roles).title,
              row.readTableOrNull(db.companies)?.name,
              row.readTable(db.roles).status,
              row.readTable(db.roles).startDate,
              row.readTable(db.roles).endDate,
            ),
        ]..sort((a, b) {
          if (a.status != b.status) return a.status.index.compareTo(b.status.index);
          return (b.endDate ?? DateTime(9999)).compareTo(a.endDate ?? DateTime(9999));
        });

    final pts = await (db.select(db.contactPoints)..where((c) => c.personId.equals(id) & c.deletedAt.isNull())).get();
    final points = [for (final c in pts) ContactPointView(c.uuid, c.kind, c.value, c.label, c.isPrimary, c.status)]
      ..sort((a, b) {
        if (a.status != b.status) return a.status.index.compareTo(b.status.index);
        if (a.kind != b.kind) return a.kind.index.compareTo(b.kind.index);
        return (b.isPrimary ? 1 : 0) - (a.isPrimary ? 1 : 0);
      });

    final cardRows =
        await (db.select(db.cards)
              ..where((c) => c.personId.equals(id) & c.deletedAt.isNull())
              ..orderBy([(c) => OrderingTerm.desc(c.scannedAt)]))
            .get();
    final cards = [for (final c in cardRows) CardView(c.uuid, c.frontSha256, c.backSha256, c.scannedAt)];

    String? introducedBy;
    if (person.introducedByPersonId != null) {
      final intro = await (db.select(
        db.people,
      )..where((p) => p.uuid.equals(person.introducedByPersonId!))).getSingleOrNull();
      introducedBy = intro?.displayName;
    }
    String? metEvent;
    if (person.metEventId != null) {
      final e = await (db.select(db.events)..where((e) => e.uuid.equals(person.metEventId!))).getSingleOrNull();
      metEvent = e?.name;
    }
    return ContactDetail(
      person: person,
      roles: roles,
      points: points,
      cards: cards,
      introducedByName: introducedBy,
      metEventName: metEvent,
    );
  }

  /// Company names for the edit form's autocomplete.
  Future<List<String>> companyNames(String prefix) async {
    final rows = await db
        .customSelect(
          'SELECT name FROM companies WHERE deleted_at IS NULL AND name LIKE ? ORDER BY name COLLATE NOCASE LIMIT 8',
          variables: [Variable.withString('${prefix.replaceAll('%', '')}%')],
        )
        .get();
    return [for (final r in rows) r.read<String>('name')];
  }

  Future<List<String>> titles(String prefix) async {
    final rows = await db
        .customSelect(
          'SELECT DISTINCT title FROM roles WHERE deleted_at IS NULL AND title != \'\' AND title LIKE ? '
          'ORDER BY title COLLATE NOCASE LIMIT 8',
          variables: [Variable.withString('${prefix.replaceAll('%', '')}%')],
        )
        .get();
    return [for (final r in rows) r.read<String>('title')];
  }

  // --------------------------------------------------------------- writes

  /// Creates (id == null) or updates a contact. Returns the person id.
  Future<String> save(ContactDraft d, {String? id, String region = 'US', RoleSource source = RoleSource.manual}) {
    return db.transaction(() async {
      final t = now();
      final personId = id ?? uuidGen.v4();
      final person = PeopleCompanion(
        first: Value(d.first.trim()),
        last: Value(d.last.trim()),
        displayName: Value(d.displayName.isEmpty ? d.company.trim() : d.displayName),
        leadRating: Value(d.leadRating),
        notes: Value(d.notes.trim()),
        followupAt: Value(d.followupAt),
        trackCareer: Value(d.trackCareer),
        updatedAt: Value(t),
      );
      if (id == null) {
        await db.into(db.people).insert(person.copyWith(uuid: Value(personId), createdAt: Value(t)));
      } else {
        final old = await (db.select(db.people)..where((p) => p.uuid.equals(id))).getSingle();
        // Moving the follow-up date reopens it.
        final reopen = old.followupAt != d.followupAt;
        await (db.update(
          db.people,
        )..where((p) => p.uuid.equals(id))).write(reopen ? person.copyWith(followupDoneAt: const Value(null)) : person);
      }

      final companyId = await _companyId(d.company, t);
      await _saveRole(personId, d.title.trim(), companyId, source, t);

      final desired = <(ContactKind, String, String)>[
        for (final p in d.phones)
          if (p.value.trim().isNotEmpty)
            (
              p.label.toLowerCase().startsWith('m') ? ContactKind.mobile : ContactKind.office,
              normalizePhone(p.value, region),
              p.label,
            ),
        for (final e in d.emails)
          if (e.trim().isNotEmpty) (ContactKind.email, e.trim().toLowerCase(), ''),
        if (d.website.trim().isNotEmpty) (ContactKind.web, d.website.trim(), ''),
        if (d.address.trim().isNotEmpty) (ContactKind.address, d.address.trim(), ''),
      ];
      await _syncPoints(personId, desired, t);
      await reindex(personId);
      return personId;
    });
  }

  /// Every card image hash saved to a person (fronts and backs), live.
  Stream<Set<String>> watchSavedCardHashes() => db
      .customSelect(
        'SELECT front_sha256 AS h FROM cards WHERE deleted_at IS NULL AND person_id IS NOT NULL '
        'UNION SELECT back_sha256 FROM cards WHERE deleted_at IS NULL AND back_sha256 IS NOT NULL',
        readsFrom: {db.cards},
      )
      .watch()
      .map((rows) => {for (final r in rows) r.read<String>('h')});

  /// Whether a card image (front or back) is already saved to someone.
  Future<bool> hasCard(String hash) async {
    final row =
        await (db.select(db.cards)
              ..where((c) => (c.frontSha256.equals(hash) | c.backSha256.equals(hash)) & c.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  /// Links a scanned card (front, optional back) to a person.
  Future<void> attachCard(
    String personId, {
    required String frontHash,
    String? backHash,
    String ocrJson = '{}',
    String? scanSessionId,
  }) async {
    final t = now();
    await db
        .into(db.cards)
        .insert(
          CardsCompanion.insert(
            personId: Value(personId),
            frontSha256: frontHash,
            backSha256: Value(backHash),
            ocrJson: Value(ocrJson),
            scanSessionId: Value(scanSessionId),
            status: const Value(CardStatus.saved),
            scannedAt: Value(t),
            createdAt: Value(t),
            updatedAt: Value(t),
          ),
        );
  }

  Future<void> delete(String id) => db.transaction(() async {
    await db.tombstonePerson(id);
    await db.customStatement('DELETE FROM person_search WHERE person_id = ?', [id]);
  });

  /// Undo for delete (the snackbar window).
  Future<void> restore(String id) => db.transaction(() async {
    await (db.update(
      db.people,
    )..where((p) => p.uuid.equals(id))).write(PeopleCompanion(deletedAt: const Value(null), updatedAt: Value(now())));
    await reindex(id);
  });

  Future<void> setLeadRating(String id, LeadRating? rating) => (db.update(
    db.people,
  )..where((p) => p.uuid.equals(id))).write(PeopleCompanion(leadRating: Value(rating), updatedAt: Value(now())));

  Future<void> setFollowup(String id, DateTime? at) => (db.update(db.people)..where((p) => p.uuid.equals(id))).write(
    PeopleCompanion(followupAt: Value(at), followupDoneAt: const Value(null), updatedAt: Value(now())),
  );

  Future<void> markFollowupDone(String id) => (db.update(
    db.people,
  )..where((p) => p.uuid.equals(id))).write(PeopleCompanion(followupDoneAt: Value(now()), updatedAt: Value(now())));

  /// Adds a dated line at the top of the notes ("2026-10-19  Called, wants a quote").
  Future<void> addNote(String id, String text) => db.transaction(() async {
    final p = await (db.select(db.people)..where((p) => p.uuid.equals(id))).getSingle();
    final line = '${DateFormat('yyyy-MM-dd').format(now())}  ${text.trim()}';
    final notes = p.notes.isEmpty ? line : '$line\n${p.notes}';
    await (db.update(
      db.people,
    )..where((p) => p.uuid.equals(id))).write(PeopleCompanion(notes: Value(notes), updatedAt: Value(now())));
    await reindex(id);
  });

  ExportContact toExport(ContactDetail d) => ExportContact(
    first: d.person.first,
    last: d.person.last,
    company: d.currentRole?.company,
    title: d.currentRole?.title,
    emails: [for (final e in d.active(ContactKind.email)) e.value],
    phones: [
      for (final p in d.active(ContactKind.mobile)) (label: 'M', number: p.value),
      for (final p in d.active(ContactKind.office)) (label: 'O', number: p.value),
    ],
    website: d.active(ContactKind.web).firstOrNull?.value,
    address: d.active(ContactKind.address).firstOrNull?.value,
    notes: d.person.notes.isEmpty ? null : d.person.notes,
  );

  // -------------------------------------------------------------- helpers

  Future<String?> _companyId(String name, DateTime t) async {
    final printed = name.trim();
    if (printed.isEmpty) return null;
    final key = companyKey(printed);
    final existing =
        await (db.select(db.companies)
              ..where((c) => c.nameNorm.equals(key) & c.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return existing.uuid;
    final id = uuidGen.v4();
    await db
        .into(db.companies)
        .insert(
          CompaniesCompanion.insert(
            uuid: Value(id),
            name: printed,
            nameNorm: key,
            createdAt: Value(t),
            updatedAt: Value(t),
          ),
        );
    return id;
  }

  /// v1 manual edits change the current role in place. Career history (S12)
  /// adds new roles instead when a scan shows a different company.
  Future<void> _saveRole(String personId, String title, String? companyId, RoleSource source, DateTime t) async {
    final current =
        await (db.select(db.roles)
              ..where(
                (r) => r.personId.equals(personId) & r.status.equalsValue(RoleStatus.current) & r.deletedAt.isNull(),
              )
              ..orderBy([(r) => OrderingTerm.desc(r.updatedAt)])
              ..limit(1))
            .getSingleOrNull();
    if (current == null) {
      if (title.isEmpty && companyId == null) return;
      await db
          .into(db.roles)
          .insert(
            RolesCompanion.insert(
              personId: personId,
              companyId: Value(companyId),
              title: Value(title),
              source: Value(source),
              confirmedAt: Value(t),
              createdAt: Value(t),
              updatedAt: Value(t),
            ),
          );
    } else if (current.title != title || current.companyId != companyId) {
      await (db.update(db.roles)..where((r) => r.uuid.equals(current.uuid))).write(
        RolesCompanion(title: Value(title), companyId: Value(companyId), confirmedAt: Value(t), updatedAt: Value(t)),
      );
    }
  }

  /// Diffs active contact points: unchanged rows stay (sync-friendly), removed
  /// ones are tombstoned, new ones inserted. Former/bounced rows are never touched.
  Future<void> _syncPoints(String personId, List<(ContactKind, String, String)> desired, DateTime t) async {
    final existing =
        await (db.select(db.contactPoints)..where(
              (c) => c.personId.equals(personId) & c.deletedAt.isNull() & c.status.equalsValue(ContactStatus.active),
            ))
            .get();
    final keep = <String>{};
    final firstOfKind = <ContactKind>{};
    for (final (kind, value, label) in desired) {
      final primary = firstOfKind.add(kind);
      final match = existing.where((e) => e.kind == kind && e.value == value && !keep.contains(e.uuid)).firstOrNull;
      if (match != null) {
        keep.add(match.uuid);
        if (match.label != label || match.isPrimary != primary) {
          await (db.update(db.contactPoints)..where((c) => c.uuid.equals(match.uuid))).write(
            ContactPointsCompanion(label: Value(label), isPrimary: Value(primary), updatedAt: Value(t)),
          );
        }
      } else {
        await db
            .into(db.contactPoints)
            .insert(
              ContactPointsCompanion.insert(
                personId: personId,
                kind: kind,
                value: value,
                label: Value(label),
                isPrimary: Value(primary),
                createdAt: Value(t),
                updatedAt: Value(t),
              ),
            );
      }
    }
    for (final e in existing.where((e) => !keep.contains(e.uuid))) {
      await (db.update(
        db.contactPoints,
      )..where((c) => c.uuid.equals(e.uuid))).write(ContactPointsCompanion(deletedAt: Value(t), updatedAt: Value(t)));
    }
  }

  /// Rebuilds one person's search row (also used by merge).
  Future<void> reindex(String personId) async {
    await db.customStatement('DELETE FROM person_search WHERE person_id = ?', [personId]);
    final d = await loadDetail(personId);
    if (d == null) return;
    final phones = d.points.where((p) => p.kind == ContactKind.mobile || p.kind == ContactKind.office);
    final body = <String>[
      d.person.first,
      d.person.last,
      d.person.displayName,
      for (final r in d.roles) ...[r.title, r.company ?? ''],
      for (final p in d.points.where((p) => p.kind != ContactKind.mobile && p.kind != ContactKind.office)) p.value,
      // FTS matches prefixes only, so phones are indexed as full digits, national
      // number, and the local 7- and 4-digit tails ("555-0142", "0142").
      for (final p in phones) ..._phoneTerms(p.value),
      d.person.notes,
      ...await _tagNames(personId),
    ].where((s) => s.isNotEmpty).join(' ');
    await db.customStatement('INSERT INTO person_search (person_id, body) VALUES (?, ?)', [personId, body]);
  }

  Future<List<String>> _tagNames(String personId) async => [
    for (final r
        in await db
            .customSelect(
              'SELECT t.name FROM person_tags pt JOIN tags t ON t.uuid = pt.tag_id '
              'WHERE pt.person_id = ? AND pt.deleted_at IS NULL AND t.deleted_at IS NULL',
              variables: [Variable.withString(personId)],
            )
            .get())
      r.read<String>('name'),
  ];

  Set<String> _phoneTerms(String value) {
    final d = digitsOnly(value);
    var national = '';
    try {
      national = PhoneNumber.parse(value).nsn;
    } catch (_) {}
    return {d, national, if (d.length > 7) d.substring(d.length - 7), if (d.length > 4) d.substring(d.length - 4)};
  }

  static T? _enum<T extends Enum>(List<T> values, String? name) =>
      name == null ? null : values.where((v) => v.name == name).firstOrNull;

  static DateTime? _date(int? secs) => secs == null ? null : DateTime.fromMillisecondsSinceEpoch(secs * 1000);
}

/// E.164 when the number is valid for [region], otherwise as typed.
String normalizePhone(String raw, String region) {
  final iso = IsoCode.values.where((c) => c.name == region.toUpperCase()).firstOrNull ?? IsoCode.US;
  try {
    final p = PhoneNumber.parse(raw, callerCountry: iso);
    if (p.isValid()) return '+${p.countryCode}${p.nsn}';
  } catch (_) {}
  return raw.trim();
}

/// Display format for an E.164 number: "+1 330-555-0142".
String formatPhone(String value) {
  if (!value.startsWith('+')) return value;
  try {
    final p = PhoneNumber.parse(value);
    return '+${p.countryCode} ${p.formatNsn()}';
  } catch (_) {
    return value;
  }
}

/// User text -> FTS5 prefix query. Null when there is nothing to search.
String? ftsQuery(String input) {
  final tokens = input
      .toLowerCase()
      .split(RegExp(r'[\s,;]+'))
      .map((t) => t.replaceAll('"', ''))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return null;
  // A token that is mostly digits searches the digits-only phone copy.
  return tokens
      .map((t) {
        final d = digitsOnly(t);
        final term = d.length >= 3 && d.length >= t.length - 3 ? d : t;
        return '"$term"*';
      })
      .join(' ');
}
