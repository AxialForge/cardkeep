import 'dart:io';
import 'dart:typed_data';

import 'package:card_organizer/core/cards/card_queue_repository.dart';
import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/events/events_repository.dart';
import 'package:card_organizer/core/images/image_store.dart';
import 'package:card_organizer/scan/scan_pipeline.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late EventsRepository events;
  late ContactsRepository contacts;
  late CardQueueRepository queue;
  var clock = DateTime(2026, 11, 3, 9);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    events = EventsRepository(db, clock: () => clock);
    contacts = ContactsRepository(db, clock: () => clock);
    final dir = await Directory.systemTemp.createTemp('ck_ev');
    addTearDown(() => dir.delete(recursive: true));
    queue = CardQueueRepository(db, ImageStore(dir), clock: () => clock);
  });
  tearDown(() => db.close());

  EventDraft fabtech({bool auto = true}) => EventDraft(
    name: 'FabTech 2026',
    start: DateTime(2026, 11, 3),
    end: DateTime(2026, 11, 5),
    location: 'Chicago, IL',
    goal: 3,
    autoScan: auto,
  );

  ScannedSide side(String hash) => ScannedSide(hash: hash, thumb: Uint8List(0), issues: const []);

  test('phases: upcoming, current, past', () async {
    final id = await events.save(fabtech());
    final e = (await events.watchEvent(id).first)!;
    expect(phaseOf(e, DateTime(2026, 11, 2, 23)), EventPhase.upcoming);
    expect(phaseOf(e, DateTime(2026, 11, 5, 23)), EventPhase.current);
    expect(phaseOf(e, DateTime(2026, 11, 6)), EventPhase.past);
  });

  test('cards scanned in a session belong to the event; saving one sets Met at', () async {
    final ev = await events.save(fabtech());
    await events.startSession(ev);
    final card = await queue.enqueue(side('a' * 64));
    expect((await events.watchActive().first)!.cards, 1);

    final p = await contacts.save(ContactDraft(first: 'Dana', last: 'Reyes', company: 'Halden'));
    await queue.link(card, p);
    expect((await contacts.loadDetail(p))!.metEventName, 'FabTech 2026');

    await events.endSession();
    expect(await events.watchActive().first, isNull);
    final later = await queue.enqueue(side('b' * 64));
    final p2 = await contacts.save(ContactDraft(first: 'Sam', last: 'Okafor'));
    await queue.link(later, p2);
    expect((await contacts.loadDetail(p2))!.metEventName, isNull);

    final s = await events.watchStats(ev).first;
    expect([s.cards, s.contacts, s.companies], [1, 1, 1]);
    expect((await events.watchPeople(ev).first).single.name, 'Dana Reyes');
  });

  test('auto-start opens once per day and respects ending it', () async {
    final ev = await events.save(fabtech());
    await events.save(EventDraft(name: 'Manual', start: clock, end: clock, autoScan: false));
    expect((await events.autoStartIfDue())?.uuid, ev);
    expect(await events.autoStartIfDue(), isNull, reason: 'already open');
    await events.endSession();
    expect(await events.autoStartIfDue(), isNull, reason: 'ended today: stays ended');
    clock = DateTime(2026, 11, 4, 8);
    expect((await events.autoStartIfDue())?.uuid, ev, reason: 'next show day');
    clock = DateTime(2026, 11, 6, 8);
    await events.endSession();
    expect(await events.autoStartIfDue(), isNull, reason: 'event over');
  });

  test('deleting an event ends its session and keeps the people', () async {
    final ev = await events.save(fabtech());
    await events.startSession(ev);
    final p = await contacts.save(ContactDraft(first: 'Dana'));
    await events.setMetAt(p, ev);
    await events.delete(ev);
    expect(await events.watchActive().first, isNull);
    expect(await events.watchEvents().first, isEmpty);
    expect(await contacts.loadDetail(p), isNotNull);
  });
}
