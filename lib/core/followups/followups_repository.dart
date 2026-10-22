import 'package:drift/drift.dart';

import '../db/database.dart';

/// One open follow-up (S11.1): a person with followup_at set and not done.
class FollowupItem {
  final String personId, name, first;
  final String? company, email, eventName;
  final DateTime due;
  const FollowupItem({
    required this.personId,
    required this.name,
    required this.first,
    required this.due,
    this.company,
    this.email,
    this.eventName,
  });
}

enum FollowupGroup {
  overdue('Overdue'),
  thisWeek('This week'),
  later('Later');

  final String label;
  const FollowupGroup(this.label);
}

FollowupGroup groupOf(DateTime due, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(due.year, due.month, due.day);
  if (day.isBefore(today)) return FollowupGroup.overdue;
  if (day.isBefore(today.add(const Duration(days: 7)))) return FollowupGroup.thisWeek;
  return FollowupGroup.later;
}

/// Follow-ups and event reminders (roadmap S11).
class FollowupsRepository {
  final AppDatabase db;
  final DateTime Function() now;
  FollowupsRepository(this.db, {DateTime Function()? clock}) : now = clock ?? DateTime.now;

  Stream<List<FollowupItem>> watchOpen() => db
      .customSelect(
        '''
SELECT p.uuid, p.display_name, p.first, p.followup_at, e.name AS event,
  (SELECT c.name FROM roles r JOIN companies c ON c.uuid = r.company_id
     WHERE r.person_id = p.uuid AND r.status = 'current' AND r.deleted_at IS NULL LIMIT 1) AS company,
  (SELECT value FROM contact_points cp WHERE cp.person_id = p.uuid AND cp.kind = 'email'
     AND cp.status = 'active' AND cp.deleted_at IS NULL ORDER BY cp.is_primary DESC LIMIT 1) AS email
FROM people p LEFT JOIN events e ON e.uuid = p.met_event_id
WHERE p.deleted_at IS NULL AND p.followup_at IS NOT NULL AND p.followup_done_at IS NULL
ORDER BY p.followup_at''',
        readsFrom: {db.people, db.roles, db.companies, db.contactPoints, db.events},
      )
      .watch()
      .map(
        (rows) => [
          for (final r in rows)
            FollowupItem(
              personId: r.read('uuid'),
              name: r.read('display_name'),
              first: r.read('first'),
              due: DateTime.fromMillisecondsSinceEpoch(r.read<int>('followup_at') * 1000),
              company: r.readNullable('company'),
              email: r.readNullable('email'),
              eventName: r.readNullable('event'),
            ),
        ],
      );

  Future<void> markDone(String personId) => _write(personId, PeopleCompanion(followupDoneAt: Value(now())));

  /// Moves the date (and reopens it).
  Future<void> reschedule(String personId, DateTime at) =>
      _write(personId, PeopleCompanion(followupAt: Value(_at8(at)), followupDoneAt: const Value(null)));

  /// S11.3: everyone met at the event gets a follow-up on end date + offset
  /// (8:00), unless they already have an open one. Returns how many were set.
  Future<int> applyEventReminders(String eventId) async {
    final e = await (db.select(db.events)..where((x) => x.uuid.equals(eventId))).getSingle();
    final due = _at8(e.endDate.add(Duration(days: e.reminderOffsetDays)));
    final t = now();
    return db.customUpdate(
      'UPDATE people SET followup_at = ?, followup_done_at = NULL, updated_at = ? '
      'WHERE met_event_id = ? AND deleted_at IS NULL AND (followup_at IS NULL OR followup_done_at IS NOT NULL)',
      variables: [Variable.withDateTime(due), Variable.withDateTime(t), Variable.withString(eventId)],
      updates: {db.people},
    );
  }

  Future<void> _write(String id, PeopleCompanion c) =>
      (db.update(db.people)..where((p) => p.uuid.equals(id))).write(c.copyWith(updatedAt: Value(now())));

  static DateTime _at8(DateTime d) => DateTime(d.year, d.month, d.day, 8);
}

/// The follow-up email (S11.8): opened in the mail app, never sent by CardKeep.
({String subject, String body}) followupEmail(FollowupItem f) {
  final hi = f.first.trim().isEmpty ? 'Hello' : 'Hi ${f.first.trim()}';
  final where = f.eventName == null ? '' : ' at ${f.eventName}';
  return (
    subject: f.eventName == null ? 'Following up' : 'Great to meet you$where',
    body: '$hi,\n\nThank you for your time$where. I wanted to follow up on our conversation.\n\nBest regards,\n',
  );
}
