import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/events/events_repository.dart';
import 'package:card_organizer/core/followups/followups_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ContactsRepository contacts;
  late FollowupsRepository followups;
  late EventsRepository events;
  final now = DateTime(2026, 11, 10, 12);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    contacts = ContactsRepository(db, clock: () => now);
    followups = FollowupsRepository(db, clock: () => now);
    events = EventsRepository(db, clock: () => now);
  });
  tearDown(() => db.close());

  test('groups: overdue, this week, later', () {
    expect(groupOf(DateTime(2026, 11, 9, 8), now), FollowupGroup.overdue);
    expect(groupOf(DateTime(2026, 11, 10, 8), now), FollowupGroup.thisWeek, reason: 'today is not overdue');
    expect(groupOf(DateTime(2026, 11, 16, 8), now), FollowupGroup.thisWeek);
    expect(groupOf(DateTime(2026, 11, 17, 8), now), FollowupGroup.later);
  });

  test('open list, done, reschedule', () async {
    final a = await contacts.save(
      ContactDraft(first: 'Dana', last: 'Reyes', emails: ['d@x.com'], followupAt: DateTime(2026, 11, 12, 8)),
    );
    await contacts.save(ContactDraft(first: 'Sam', last: 'Okafor', followupAt: DateTime(2026, 11, 8, 8)));
    await contacts.save(ContactDraft(first: 'No', last: 'Followup'));
    var open = await followups.watchOpen().first;
    expect(open.map((f) => f.first), ['Sam', 'Dana']);
    expect(open.last.email, 'd@x.com');

    await followups.markDone(a);
    open = await followups.watchOpen().first;
    expect(open.map((f) => f.first), ['Sam']);

    await followups.reschedule(a, DateTime(2026, 12, 1, 17));
    open = await followups.watchOpen().first;
    expect(open.last.due, DateTime(2026, 12, 1, 8));
  });

  test('event reminders: end date + offset, open ones untouched', () async {
    final ev = await events.save(
      EventDraft(name: 'FabTech', start: DateTime(2026, 11, 3), end: DateTime(2026, 11, 5), reminderOffsetDays: 2),
    );
    final a = await contacts.save(ContactDraft(first: 'Dana'));
    final b = await contacts.save(ContactDraft(first: 'Sam', followupAt: DateTime(2026, 11, 20, 8)));
    await events.setMetAt(a, ev);
    await events.setMetAt(b, ev);
    expect(await followups.applyEventReminders(ev), 1);
    final open = {for (final f in await followups.watchOpen().first) f.first: f};
    expect(open['Dana']!.due, DateTime(2026, 11, 7, 8));
    expect(open['Dana']!.eventName, 'FabTech');
    expect(open['Sam']!.due, DateTime(2026, 11, 20, 8));
    final mail = followupEmail(open['Dana']!);
    expect(mail.subject, 'Great to meet you at FabTech');
    expect(mail.body, startsWith('Hi Dana,'));
  });
}
