import 'package:drift/drift.dart';

import '../db/database.dart';

enum EventPhase { current, upcoming, past }

/// What the new/edit event form holds.
class EventDraft {
  String name;
  EventType type;
  DateTime start, end; // dates (time ignored)
  String location;
  String booth;
  int? goal;
  String notes;
  bool autoScan;
  int reminderOffsetDays;

  EventDraft({
    this.name = '',
    this.type = EventType.tradeShow,
    required this.start,
    required this.end,
    this.location = '',
    this.booth = '',
    this.goal,
    this.notes = '',
    this.autoScan = true,
    this.reminderOffsetDays = 2,
  });

  factory EventDraft.of(Event e) => EventDraft(
    name: e.name,
    type: e.type,
    start: e.startDate,
    end: e.endDate,
    location: e.location,
    booth: e.booth ?? '',
    goal: e.goal,
    notes: e.notes,
    autoScan: e.autoScan,
    reminderOffsetDays: e.reminderOffsetDays,
  );
}

/// Counts for the event page (S10.5): all queries, nothing stored.
class EventStats {
  final int cards, contacts, companies, followupsDue, followupsDone;
  const EventStats(this.cards, this.contacts, this.companies, this.followupsDue, this.followupsDone);
}

class MetPerson {
  final String id, name;
  final String? company;
  const MetPerson(this.id, this.name, this.company);
}

/// The open scan session and its event, if any.
class ActiveSession {
  final String sessionId;
  final Event event;
  final int cards;
  const ActiveSession(this.sessionId, this.event, this.cards);
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

EventPhase phaseOf(Event e, DateTime now) {
  final today = _day(now);
  if (today.isBefore(_day(e.startDate))) return EventPhase.upcoming;
  if (today.isAfter(_day(e.endDate))) return EventPhase.past;
  return EventPhase.current;
}

/// Trade shows and networking events with scan sessions (roadmap S10).
class EventsRepository {
  final AppDatabase db;
  final DateTime Function() now;

  EventsRepository(this.db, {DateTime Function()? clock}) : now = clock ?? DateTime.now;

  Stream<List<Event>> watchEvents() =>
      (db.select(db.events)
            ..where((e) => e.deletedAt.isNull())
            ..orderBy([(e) => OrderingTerm.desc(e.startDate)]))
          .watch();

  Stream<Event?> watchEvent(String id) =>
      (db.select(db.events)..where((e) => e.uuid.equals(id) & e.deletedAt.isNull())).watchSingleOrNull();

  Future<String> save(EventDraft d, {String? id}) async {
    final t = now();
    final row = EventsCompanion(
      name: Value(d.name.trim()),
      type: Value(d.type),
      startDate: Value(_day(d.start)),
      endDate: Value(_day(d.end.isBefore(d.start) ? d.start : d.end)),
      location: Value(d.location.trim()),
      booth: Value(d.booth.trim().isEmpty ? null : d.booth.trim()),
      goal: Value(d.goal),
      notes: Value(d.notes.trim()),
      autoScan: Value(d.autoScan),
      reminderOffsetDays: Value(d.reminderOffsetDays),
      updatedAt: Value(t),
    );
    if (id == null) {
      final newId = uuidGen.v4();
      await db.into(db.events).insert(row.copyWith(uuid: Value(newId), createdAt: Value(t)));
      return newId;
    }
    await (db.update(db.events)..where((e) => e.uuid.equals(id))).write(row);
    return id;
  }

  /// Tombstones the event; people met there keep the link (S10.7).
  Future<void> delete(String id) async {
    final t = now();
    await endSessionsFor(id);
    await (db.update(
      db.events,
    )..where((e) => e.uuid.equals(id))).write(EventsCompanion(deletedAt: Value(t), updatedAt: Value(t)));
  }

  // ------------------------------------------------------------ sessions

  Stream<ActiveSession?> watchActive() => db
      .customSelect(
        '''
SELECT s.uuid AS sid, s.event_id,
  (SELECT COUNT(*) FROM cards c WHERE c.scan_session_id = s.uuid AND c.deleted_at IS NULL) AS n
FROM scan_sessions s JOIN events e ON e.uuid = s.event_id
WHERE s.ended_at IS NULL AND s.deleted_at IS NULL AND e.deleted_at IS NULL
ORDER BY s.started_at DESC LIMIT 1''',
        readsFrom: {db.scanSessions, db.events, db.cards},
      )
      .watch()
      .asyncMap((rows) async {
        if (rows.isEmpty) return null;
        final r = rows.single;
        final e = await (db.select(db.events)..where((x) => x.uuid.equals(r.read<String>('event_id')))).getSingle();
        return ActiveSession(r.read<String>('sid'), e, r.read<int>('n'));
      });

  /// The open session id, for stamping new cards (null = none).
  Future<String?> activeSessionId() async => (await watchActive().first)?.sessionId;

  /// Opens a session for [eventId] (closing any other): every card scanned
  /// until it ends belongs to the event (S10.3).
  Future<String> startSession(String eventId) async {
    await endSession();
    final t = now();
    final id = uuidGen.v4();
    await db
        .into(db.scanSessions)
        .insert(
          ScanSessionsCompanion.insert(
            uuid: Value(id),
            eventId: Value(eventId),
            startedAt: Value(t),
            createdAt: Value(t),
            updatedAt: Value(t),
          ),
        );
    return id;
  }

  Future<void> endSession() async {
    final t = now();
    await (db.update(
      db.scanSessions,
    )..where((s) => s.endedAt.isNull())).write(ScanSessionsCompanion(endedAt: Value(t), updatedAt: Value(t)));
  }

  Future<void> endSessionsFor(String eventId) async {
    final t = now();
    await (db.update(db.scanSessions)..where((s) => s.endedAt.isNull() & s.eventId.equals(eventId))).write(
      ScanSessionsCompanion(endedAt: Value(t), updatedAt: Value(t)),
    );
  }

  /// On app open (S10.4): an auto-scan event running today gets a session,
  /// unless one is open or one for it was already started today (so ending it
  /// sticks). Returns the event when a session was started.
  Future<Event?> autoStartIfDue() async {
    if (await activeSessionId() != null) return null;
    final today = _day(now());
    final events = await (db.select(db.events)..where((e) => e.deletedAt.isNull() & e.autoScan.equals(true))).get();
    for (final e in events) {
      if (phaseOf(e, today) != EventPhase.current) continue;
      final startedToday =
          await (db.select(db.scanSessions)
                ..where((s) => s.eventId.equals(e.uuid) & s.startedAt.isBiggerOrEqualValue(today))
                ..limit(1))
              .getSingleOrNull();
      if (startedToday != null) continue;
      await startSession(e.uuid);
      return e;
    }
    return null;
  }

  // ---------------------------------------------------------------- detail

  Stream<EventStats> watchStats(String eventId) => db
      .customSelect(
        '''
SELECT
  (SELECT COUNT(*) FROM cards c JOIN scan_sessions s ON s.uuid = c.scan_session_id
     WHERE s.event_id = ?1 AND c.deleted_at IS NULL) AS cards,
  (SELECT COUNT(*) FROM people WHERE met_event_id = ?1 AND deleted_at IS NULL) AS people,
  (SELECT COUNT(DISTINCT r.company_id) FROM roles r JOIN people p ON p.uuid = r.person_id
     WHERE p.met_event_id = ?1 AND p.deleted_at IS NULL AND r.deleted_at IS NULL
       AND r.status = 'current' AND r.company_id IS NOT NULL) AS companies,
  (SELECT COUNT(*) FROM people WHERE met_event_id = ?1 AND deleted_at IS NULL
     AND followup_at IS NOT NULL AND followup_done_at IS NULL) AS due,
  (SELECT COUNT(*) FROM people WHERE met_event_id = ?1 AND deleted_at IS NULL
     AND followup_done_at IS NOT NULL) AS done''',
        variables: [Variable.withString(eventId)],
        readsFrom: {db.cards, db.scanSessions, db.people, db.roles},
      )
      .watch()
      .map((rows) {
        final r = rows.single;
        return EventStats(r.read('cards'), r.read('people'), r.read('companies'), r.read('due'), r.read('done'));
      });

  Stream<List<MetPerson>> watchPeople(String eventId) => db
      .customSelect(
        '''
SELECT p.uuid, p.display_name,
  (SELECT c.name FROM roles r JOIN companies c ON c.uuid = r.company_id
     WHERE r.person_id = p.uuid AND r.status = 'current' AND r.deleted_at IS NULL LIMIT 1) AS company
FROM people p WHERE p.met_event_id = ? AND p.deleted_at IS NULL ORDER BY p.created_at DESC''',
        variables: [Variable.withString(eventId)],
        readsFrom: {db.people, db.roles, db.companies},
      )
      .watch()
      .map(
        (rows) => [for (final r in rows) MetPerson(r.read('uuid'), r.read('display_name'), r.readNullable('company'))],
      );

  /// Marks a person as met at an event (also used when a card from a session
  /// is saved).
  Future<void> setMetAt(String personId, String? eventId) => (db.update(
    db.people,
  )..where((p) => p.uuid.equals(personId))).write(PeopleCompanion(metEventId: Value(eventId), updatedAt: Value(now())));
}
