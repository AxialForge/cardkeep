import 'package:drift/drift.dart';

import '../db/database.dart';
import 'contact_models.dart';

/// An event where you met someone from the company.
class CompanyEvent {
  final String id, name;
  final DateTime start;
  const CompanyEvent(this.id, this.name, this.start);
}

/// Everything the company page shows (S14d.2).
class CompanyOverview {
  final String id, name;
  final String? website, address, logo;
  final List<ContactSummary> current, former, places;
  final List<CompanyEvent> events;
  final DateTime? lastContact;
  final List<String> sharedPhones;

  const CompanyOverview({
    required this.id,
    required this.name,
    this.website,
    this.address,
    this.logo,
    this.current = const [],
    this.former = const [],
    this.places = const [],
    this.events = const [],
    this.lastContact,
    this.sharedPhones = const [],
  });

  List<ContactSummary> get everyone => [...current, ...former, ...places];
}

/// Reads for the company page. Writes stay in ContactsRepository.
class CompanyRepository {
  final AppDatabase db;
  CompanyRepository(this.db);

  /// Re-reads whenever people, roles, cards or contact points change.
  Stream<CompanyOverview?> watch(String id) => db
      .customSelect('SELECT 1', readsFrom: {db.people, db.roles, db.companies, db.cards, db.contactPoints, db.events})
      .watch()
      .asyncMap((_) => load(id));

  Future<CompanyOverview?> load(String id) async {
    final c = await (db.select(db.companies)..where((x) => x.uuid.equals(id) & x.deletedAt.isNull())).getSingleOrNull();
    if (c == null) return null;
    final v = [Variable.withString(id)];

    // Everyone with a live role here; a current role wins over a former one.
    final rows = await db.customSelect('''
SELECT p.uuid, p.first, p.last, p.display_name, p.lead_rating, p.status, p.followup_at, p.created_at,
       p.logo_sha256, p.kind, p.place_category, r.title, r.status AS role_status
FROM roles r JOIN people p ON p.uuid = r.person_id
WHERE r.company_id = ? AND r.deleted_at IS NULL AND p.deleted_at IS NULL
ORDER BY (r.status = 'current') DESC, p.display_name COLLATE NOCASE''', variables: v).get();
    final current = <ContactSummary>[], former = <ContactSummary>[], places = <ContactSummary>[];
    final seen = <String>{};
    String? logo;
    for (final r in rows) {
      final pid = r.read<String>('uuid');
      if (!seen.add(pid)) continue;
      final kind = _enum(PersonKind.values, r.read<String>('kind')) ?? PersonKind.person;
      final s = ContactSummary(
        id: pid,
        first: r.read<String>('first'),
        last: r.read<String>('last'),
        displayName: r.read<String>('display_name'),
        title: r.readNullable<String>('title'),
        company: c.name,
        companyId: id,
        leadRating: _enum(LeadRating.values, r.readNullable<String>('lead_rating')),
        status: _enum(PersonStatus.values, r.read<String>('status')) ?? PersonStatus.active,
        followupAt: _date(r.readNullable<int>('followup_at')),
        createdAt: _date(r.read<int>('created_at'))!,
        logo: r.readNullable<String>('logo_sha256'),
        kind: kind,
        category: r.readNullable<String>('place_category'),
      );
      // A place's logo is the business's own; otherwise the first person's.
      if (s.logo != null && (logo == null || kind == PersonKind.place)) logo = s.logo;
      if (kind == PersonKind.place) {
        places.add(s);
      } else if (r.read<String>('role_status') == RoleStatus.current.name) {
        current.add(s);
      } else {
        former.add(s);
      }
    }

    const who = 'SELECT person_id FROM roles WHERE company_id = ? AND deleted_at IS NULL';
    final events = [
      for (final e in await db.customSelect('''
SELECT DISTINCT e.uuid, e.name, e.start_date FROM events e JOIN people p ON p.met_event_id = e.uuid
WHERE e.deleted_at IS NULL AND p.deleted_at IS NULL AND p.uuid IN ($who)
ORDER BY e.start_date DESC''', variables: v).get())
        CompanyEvent(e.read<String>('uuid'), e.read<String>('name'), _date(e.read<int>('start_date'))!),
    ];

    final last = await db.customSelect('''
SELECT MAX(COALESCE((SELECT MAX(scanned_at) FROM cards k WHERE k.person_id = p.uuid AND k.deleted_at IS NULL),
                    p.created_at)) AS t
FROM people p WHERE p.deleted_at IS NULL AND p.uuid IN ($who)''', variables: v).getSingle();

    // Phones the company shares: an office number on two or more people, or a place's numbers.
    final phones = [
      for (final r in await db.customSelect('''
SELECT cp.value FROM contact_points cp JOIN people p ON p.uuid = cp.person_id
WHERE cp.deleted_at IS NULL AND p.deleted_at IS NULL AND p.uuid IN ($who)
  AND (cp.kind = 'office' OR (p.kind = 'place' AND cp.kind IN ('office', 'mobile')))
GROUP BY cp.value
HAVING COUNT(DISTINCT cp.person_id) > 1 OR MAX(p.kind = 'place') = 1
ORDER BY COUNT(DISTINCT cp.person_id) DESC''', variables: v).get())
        r.read<String>('value'),
    ];

    String? website = c.website;
    if (website == null || website.isEmpty) {
      website = (await db.customSelect('''
SELECT cp.value FROM contact_points cp JOIN people p ON p.uuid = cp.person_id
WHERE cp.kind = 'web' AND cp.deleted_at IS NULL AND p.deleted_at IS NULL AND p.uuid IN ($who)
GROUP BY lower(cp.value) ORDER BY COUNT(*) DESC LIMIT 1''', variables: v).getSingleOrNull())?.read<String>('value');
    }

    return CompanyOverview(
      id: id,
      name: c.name,
      website: website,
      address: c.address,
      logo: logo,
      current: current,
      former: former,
      places: places,
      events: events,
      lastContact: _date(last.readNullable<int>('t')),
      sharedPhones: phones,
    );
  }

  static T? _enum<T extends Enum>(List<T> values, String? name) =>
      name == null ? null : values.where((v) => v.name == name).firstOrNull;
  static DateTime? _date(int? secs) => secs == null ? null : DateTime.fromMillisecondsSinceEpoch(secs * 1000);
}
