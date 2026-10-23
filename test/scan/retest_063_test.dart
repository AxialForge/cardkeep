// Cases from the 0.6.3 phone retest (docs/phone-tests/0.6.2-results.md, F36-F39).
import 'dart:io';
import 'dart:typed_data';

import 'package:card_organizer/core/cards/card_queue_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/images/image_store.dart';
import 'package:card_organizer/parser/ocr.dart';
import 'package:card_organizer/parser/rules.dart';
import 'package:card_organizer/scan/scan_pipeline.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

ScannedSide side(String hash, List<String> lines) =>
    ScannedSide(hash: hash, thumb: Uint8List(0), issues: const [], ocr: OcrPage.fromText(lines));

void main() {
  group('F38: the domain spells the company', () {
    test('a logo swirl read as a leading letter is dropped', () {
      expect(alignCompanyToDomain('Oenpress LLC', 'enpress'), 'Enpress LLC');
      expect(alignCompanyToDomain('OENPRESS LLC', 'enpress'), 'ENPRESS LLC');
    });

    test('names that already match, or differ more, are left alone', () {
      expect(alignCompanyToDomain('Enpress LLC', 'enpress'), 'Enpress LLC');
      expect(alignCompanyToDomain('Northwind Forging', 'enpress'), 'Northwind Forging');
      expect(alignCompanyToDomain('Bridgestone Inc', 'bridgestone'), 'Bridgestone Inc');
    });

    test('a parsed ENPRESS card loses the stray letter', () {
      final c = parseCard(
        OcrPage.fromText(
          ['OENPRESS LLC', 'ROBERT J. PRISTAS', 'PRODUCT ENGINEER', 'E-Mail bpristas@enpress.com', 'www.enpress.com'],
          heights: [22, 14, 9, 8, 8],
        ),
      );
      expect(c.company?.value, 'Enpress LLC');
    });
  });

  group('F36: the turn that reads best', () {
    test('the card as captured stays unless another turn is clearly better', () {
      expect(bestRotation({0: 0.7, 90: 0.75, 270: 0.2}), 0);
      expect(bestRotation({0: 0.2, 90: 0.85, 270: 0.3}), 90);
      expect(bestRotation({0: 0.1, 90: 0.3, 270: 0.9}), 270);
      expect(bestRotation({0: 0.3, 180: 0.8}), 180);
      expect(bestRotation({0: 0.5}), 0);
    });
  });

  group('F39: the same card is not queued twice', () {
    late AppDatabase db;
    late Directory dir;
    late CardQueueRepository q;
    var clock = DateTime(2026, 10, 23, 12);

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      dir = await Directory.systemTemp.createTemp('ck_retest');
      clock = DateTime(2026, 10, 23, 12);
      q = CardQueueRepository(db, ImageStore(dir), clock: () => clock);
    });
    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    final robert = ['Enpress LLC', 'Robert J. Pristas', 'Product Engineer', 'bpristas@enpress.com'];

    test('a re-shot of a card waiting in the queue is spotted', () async {
      expect(await q.recentlyCaptured(side('a', robert)), isFalse);
      await q.enqueue(side('a', robert));
      expect(await q.recentlyCaptured(side('b', robert)), isTrue);
      expect(
        await q.recentlyCaptured(side('c', ['Enpress LLC', 'Justin Fink', 'Sales', 'jfink@enpress.com'])),
        isFalse,
        reason: 'a colleague from the same company is a different card',
      );
    });

    test('a discarded card does not block a retake', () async {
      final id = await q.enqueue(side('a', robert));
      await q.discard(id);
      expect(await q.recentlyCaptured(side('b', robert)), isFalse);
    });

    test('cards without a name and an email or phone are never treated as repeats', () async {
      final bare = ['Enpress LLC', 'www.enpress.com'];
      await q.enqueue(side('a', bare));
      expect(CardQueueRepository.cardKey(side('b', bare)), isNull);
      expect(await q.recentlyCaptured(side('b', bare)), isFalse);
    });
  });
}
