import 'dart:convert';

import 'package:drift/drift.dart';

import '../../parser/rules.dart' show ParsedCard;
import '../../scan/scan_pipeline.dart';
import '../contacts/contact_models.dart';
import '../contacts/contacts_repository.dart';
import '../db/database.dart';
import '../dupes/matcher.dart' show jaroWinkler;
import '../images/image_store.dart';

/// A scanned card waiting for review (cards row with no person yet).
class QueueItem {
  final String cardId;
  final ScannedSide front;
  final ScannedSide? back;
  final DateTime scannedAt;
  const QueueItem(this.cardId, this.front, this.back, this.scannedAt);

  /// Why it's waiting, shown as chips in the queue.
  List<String> get reasons => [
    if (front.manualCrop) 'No edges found',
    for (final i in front.issues)
      if (!front.manualCrop || i.name != 'noCard') i.chip,
    if (front.ocr == null) 'Not read',
    if (front.check.isNotEmpty) 'Low confidence',
    if (front.parsed?.name == null && front.ocr != null) 'No name found',
  ];
}

class QueueStats {
  final int waiting, savedToday, autoSavedToday;
  const QueueStats(this.waiting, this.savedToday, this.autoSavedToday);
}

/// The review queue (spec §3 cards table; S7). Cards are stored the moment
/// they are read, so nothing scanned is lost if the app closes before review.
class CardQueueRepository {
  final AppDatabase db;
  final ImageStore store;
  final DateTime Function() now;
  CardQueueRepository(this.db, this.store, {DateTime Function()? clock}) : now = clock ?? DateTime.now;

  static String _json(ScannedSide front, ScannedSide? back, {bool auto = false}) =>
      jsonEncode({'front': front.toJson(), 'back': ?back?.toJson(), if (auto) 'auto': true});

  Future<String> enqueue(ScannedSide front, {ScannedSide? back, String? scanSessionId}) async {
    final t = now();
    // Cards scanned during an event's scan session belong to it (S10.3).
    scanSessionId ??= await _openSession();
    final id = uuidGen.v4();
    await db
        .into(db.cards)
        .insert(
          CardsCompanion.insert(
            uuid: Value(id),
            frontSha256: front.hash,
            backSha256: Value(back?.hash),
            ocrJson: Value(_json(front, back)),
            scanSessionId: Value(scanSessionId),
            status: const Value(CardStatus.needsReview),
            scannedAt: Value(t),
            createdAt: Value(t),
            updatedAt: Value(t),
          ),
        );
    return id;
  }

  /// Who a card is, for spotting the same card captured twice: name plus first
  /// email or phone digits. Null when the card doesn't say enough to tell.
  static String? cardKey(ScannedSide side) {
    final p = side.parsed;
    final name = p?.name?.value.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (p == null || name == null || name.isEmpty) return null;
    final email = p.emails.firstOrNull?.value.toLowerCase();
    final phone = p.phones.firstOrNull?.value.replaceAll(RegExp(r'\D'), '');
    final contact = email ?? (phone == null || phone.length < 7 ? null : phone);
    return contact == null ? null : '$name|$contact';
  }

  /// True when [a] and [b] are the same card read twice. Readings of one card
  /// differ ("Rosa Delga", "Hr Manage" for a name), so any shared phone (7+
  /// digits) or email is enough; otherwise the name and company must both be
  /// close (second sweep test).
  static bool sameCard(ScannedSide a, ScannedSide b) {
    final p = a.parsed, q = b.parsed;
    if (p == null || q == null) return false;
    Set<String> phones(ParsedCard c) => {
      for (final f in [...c.phones, ...c.faxes])
        if (f.value.replaceAll(RegExp(r'\D'), '') case final d when d.length >= 7) d.substring(d.length - 7),
    };
    Set<String> emails(ParsedCard c) => {for (final e in c.emails) e.value.toLowerCase().trim()};
    if (phones(p).intersection(phones(q)).isNotEmpty) return true;
    if (emails(p).intersection(emails(q)).isNotEmpty) return true;
    String norm(String? s) => (s ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final n1 = norm(p.name?.value), n2 = norm(q.name?.value);
    final c1 = norm(p.company?.value), c2 = norm(q.company?.value);
    if (n1.isEmpty || n2.isEmpty || c1.isEmpty || c2.isEmpty) return false;
    return jaroWinkler(n1, n2) >= 0.85 && jaroWinkler(c1, c2) >= 0.8;
  }

  /// True when the same card is already waiting in the queue or was captured in
  /// the last [window] (Batch, Pile and Sweep re-shoots, phone test F39).
  Future<bool> recentlyCaptured(ScannedSide side, {Duration window = const Duration(minutes: 15)}) async {
    if (side.parsed == null) return false;
    final cutoff = now().subtract(window);
    final rows =
        await (db.select(db.cards)..where(
              (c) =>
                  c.deletedAt.isNull() &
                  (c.status.equalsValue(CardStatus.needsReview) | c.createdAt.isBiggerOrEqualValue(cutoff)),
            ))
            .get();
    for (final r in rows) {
      try {
        final front = (jsonDecode(r.ocrJson) as Map)['front'];
        if (front is! Map<String, Object?>) continue;
        if (sameCard(side, ScannedSide.fromJson(r.frontSha256, Uint8List(0), front))) return true;
      } catch (_) {}
    }
    return false;
  }

  /// Takes every card out of the review queue at once ("Remove all"). Returns
  /// their ids, for [restoreAll].
  Future<List<String>> discardAll() => db.transaction(() async {
    final rows = await (db.select(db.cards)..where((c) => c.personId.isNull() & c.deletedAt.isNull())).get();
    final t = now();
    final ids = [for (final r in rows) r.uuid];
    await (db.update(
      db.cards,
    )..where((c) => c.uuid.isIn(ids))).write(CardsCompanion(deletedAt: Value(t), updatedAt: Value(t)));
    return ids;
  });

  /// Undo for [discardAll].
  Future<void> restoreAll(List<String> ids) => (db.update(
    db.cards,
  )..where((c) => c.uuid.isIn(ids))).write(CardsCompanion(deletedAt: const Value(null), updatedAt: Value(now())));
  Future<void> setBack(String cardId, ScannedSide front, ScannedSide back) =>
      (db.update(db.cards)..where((c) => c.uuid.equals(cardId))).write(
        CardsCompanion(backSha256: Value(back.hash), ocrJson: Value(_json(front, back)), updatedAt: Value(now())),
      );

  Future<String?> _openSession() async {
    final r = await db
        .customSelect(
          'SELECT s.uuid FROM scan_sessions s JOIN events e ON e.uuid = s.event_id '
          'WHERE s.ended_at IS NULL AND s.deleted_at IS NULL AND e.deleted_at IS NULL '
          'ORDER BY s.started_at DESC LIMIT 1',
        )
        .getSingleOrNull();
    return r?.read<String>('uuid');
  }

  /// Links the card to the saved person and takes it out of the queue. A card
  /// from an event's scan session sets the person's "Met at" (S10.7).
  Future<void> link(String cardId, String personId, {bool auto = false}) => db.transaction(() async {
    final row = await (db.select(db.cards)..where((c) => c.uuid.equals(cardId))).getSingle();
    // The card's logo becomes the contact's avatar unless they already have one.
    try {
      final logo = ((jsonDecode(row.ocrJson) as Map)['front'] as Map?)?['logo'];
      if (logo is String) {
        await db.customStatement('UPDATE people SET logo_sha256 = ? WHERE uuid = ? AND logo_sha256 IS NULL', [
          logo,
          personId,
        ]);
      }
    } catch (_) {}
    if (row.scanSessionId != null) {
      await db.customStatement(
        'UPDATE people SET met_event_id = (SELECT event_id FROM scan_sessions WHERE uuid = ?) '
        'WHERE uuid = ? AND met_event_id IS NULL',
        [row.scanSessionId, personId],
      );
    }
    var json = row.ocrJson;
    if (auto) {
      final m = jsonDecode(json) as Map<String, Object?>..['auto'] = true;
      json = jsonEncode(m);
    }
    await (db.update(db.cards)..where((c) => c.uuid.equals(cardId))).write(
      CardsCompanion(
        personId: Value(personId),
        status: const Value(CardStatus.saved),
        ocrJson: Value(json),
        updatedAt: Value(now()),
      ),
    );
  });

  /// Removes a card from the queue (tombstone). Its images stay until the
  /// purge after the undo window, and only go when no other card uses the same
  /// hash (audit MOB-REL-0008; see purgeDeleted).
  Future<void> discard(String cardId) => (db.update(
    db.cards,
  )..where((c) => c.uuid.equals(cardId))).write(CardsCompanion(deletedAt: Value(now()), updatedAt: Value(now())));

  Future<void> restore(String cardId) => (db.update(
    db.cards,
  )..where((c) => c.uuid.equals(cardId))).write(CardsCompanion(deletedAt: const Value(null), updatedAt: Value(now())));

  Stream<List<QueueItem>> watchQueue() =>
      (db.select(db.cards)
            ..where((c) => c.personId.isNull() & c.deletedAt.isNull())
            ..orderBy([(c) => OrderingTerm.asc(c.scannedAt)]))
          .watch()
          .asyncMap((rows) async => [for (final r in rows) ?await _item(r)]);

  Future<QueueItem?> item(String cardId) async {
    final r = await (db.select(db.cards)..where((c) => c.uuid.equals(cardId))).getSingleOrNull();
    return r == null ? null : _item(r);
  }

  Future<QueueItem?> _item(Card r) async {
    try {
      final j = jsonDecode(r.ocrJson) as Map<String, Object?>;
      Future<Uint8List> thumb(String h) async =>
          store.thumb(h).existsSync() ? await store.thumb(h).readAsBytes() : Uint8List(0);
      final front = ScannedSide.fromJson(
        r.frontSha256,
        await thumb(r.frontSha256),
        j['front']! as Map<String, Object?>,
      );
      final b = j['back'];
      final back = b is Map<String, Object?> && r.backSha256 != null
          ? ScannedSide.fromJson(r.backSha256!, await thumb(r.backSha256!), b)
          : null;
      return QueueItem(r.uuid, front, back, r.scannedAt);
    } catch (_) {
      return null; // unreadable row: skipped, never crashes the queue
    }
  }

  Stream<QueueStats> watchStats() {
    final t = now();
    final midnight = DateTime(t.year, t.month, t.day);
    return db
        .customSelect(
          '''
SELECT
  (SELECT COUNT(*) FROM cards WHERE person_id IS NULL AND deleted_at IS NULL) AS waiting,
  (SELECT COUNT(*) FROM cards WHERE person_id IS NOT NULL AND deleted_at IS NULL AND scanned_at >= ?) AS saved,
  (SELECT COUNT(*) FROM cards WHERE person_id IS NOT NULL AND deleted_at IS NULL AND scanned_at >= ?
     AND ocr_json LIKE '%"auto":true%') AS auto''',
          variables: [Variable.withDateTime(midnight), Variable.withDateTime(midnight)],
          readsFrom: {db.cards},
        )
        .watch()
        .map((rows) {
          final r = rows.single;
          return QueueStats(r.read<int>('waiting'), r.read<int>('saved'), r.read<int>('auto'));
        });
  }

  /// Saves a clean card straight to Contacts (deep dive §2.11 auto-save).
  Future<String> autoSave(String cardId, ScannedSide front, ContactsRepository contacts) async {
    final draft = draftFromScan(front.parsed);
    final id = await contacts.save(_trim(draft), region: front.region, source: RoleSource.scan);
    await link(cardId, id, auto: true);
    return id;
  }

  static ContactDraft _trim(ContactDraft d) => d
    ..phones = d.phones.where((p) => p.value.isNotEmpty).toList()
    ..emails = d.emails.where((e) => e.isNotEmpty).toList();
}
