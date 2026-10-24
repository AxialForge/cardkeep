import 'dart:io';
import 'dart:typed_data';

import 'package:card_organizer/core/cards/card_queue_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/images/image_store.dart';
import 'package:card_organizer/parser/ocr.dart';
import 'package:card_organizer/scan/card_detector.dart';
import 'package:card_organizer/scan/geometry.dart';
import 'package:card_organizer/scan/quality.dart';
import 'package:card_organizer/scan/scan_pipeline.dart';
import 'package:card_organizer/scan/sweep_tracker.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Quad rect(double x, double y, double w, double h) => Quad([Pt(x, y), Pt(x + w, y), Pt(x + w, y + h), Pt(x, y + h)]);

const w = 480.0, h = 640.0;

ScannedSide side(List<String> lines, {double? conf, List<QualityIssue> issues = const []}) => ScannedSide(
  hash: 'x',
  thumb: Uint8List(0),
  issues: issues,
  ocr: conf == null
      ? OcrPage.fromText(lines)
      : OcrPage([
          for (var i = 0; i < lines.length; i++) OcrLine(lines[i], top: i * 20.0, height: 12, confidence: conf),
        ]),
);

void main() {
  late DateTime t0;
  setUp(() => t0 = DateTime(2026, 10, 23, 20));
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  group('a logo box inside a card is not a card (fifth sweep test: Maxpak)', () {
    final card = rect(100, 200, 280, 160);
    final box = rect(160, 230, 70, 40); // logo box, centre inside the card, ~10% of its area

    test('the box is never drawn or tracked when the card is in the same frame', () {
      final t = SweepTracker();
      t.update([box, card], [60, 60], width: w, height: h, now: at(0));
      expect(t.tracks.length, 1);
      expect(t.tracks.single.quad.area, card.area);
      // Whichever order the detector lists them.
      final u = SweepTracker();
      u.update([card, box], [60, 60], width: w, height: h, now: at(0));
      expect(u.tracks.single.quad.area, card.area);
    });

    test('the box was captured first: when the card appears the box track is replaced', () {
      final t = SweepTracker();
      t.update([box], [60], width: w, height: h, now: at(0));
      final boxId = t.tracks.single.id;
      t.markReading(boxId);
      t.markDone(boxId);
      expect(t.doneCount, 1);
      t.update([card], [60], width: w, height: h, now: at(200));
      final swaps = t.takeSuperseded();
      expect(swaps.single.$1, boxId);
      expect(swaps.single.$2, t.tracks.single.id);
      expect(t.tracks.length, 1);
      expect(t.doneCount, 0, reason: 'the junk entry no longer counts; the card will');
      expect(t.takeSuperseded(), isEmpty, reason: 'each swap is reported once');
    });

    test('a box of card size inside a bigger outline is left alone (two cards)', () {
      final t = SweepTracker();
      final big = rect(60, 100, 360, 220);
      final inner = rect(100, 120, 240, 150); // 45% of big: a real card, not a logo
      t.update([big, inner], [60, 60], width: w, height: h, now: at(0));
      expect(t.tracks.length, 2);
    });
  });

  group('ghost outlines on bare table (fifth sweep test: frame 1)', () {
    test('no print, or too small: not drawn', () {
      final t = SweepTracker();
      t.update(
        [rect(40, 40, 60, 50), rect(300, 400, 70, 60), rect(100, 300, 150, 90)],
        [3, 20, 2], // tiny, small with weak print, card-size bare table
        width: w,
        height: h,
        now: at(0),
      );
      expect(t.tracks, isEmpty, reason: 'under 3% of the view needs print 30+; card-size needs 8+');
    });

    test('a lone small card with strong print is kept; beside a real card it is a ghost', () {
      final lone = SweepTracker();
      lone.update([rect(300, 400, 70, 60)], [45], width: w, height: h, now: at(0));
      expect(lone.tracks.length, 1);
      final beside = SweepTracker();
      beside.update([rect(300, 400, 70, 60), rect(40, 40, 200, 120)], [45, 60], width: w, height: h, now: at(0));
      expect(beside.tracks.length, 1);
      expect(beside.tracks.single.quad.area, 200 * 120);
    });

    test('print is judged against the sharpest card in view', () {
      expect(sweepDrawOk(rect(0, 0, 200, 120), 9, width: w, height: h, bar: 8), isTrue);
      expect(sweepDrawOk(rect(0, 0, 200, 120), 9, width: w, height: h, bar: 20), isFalse);
      final t = SweepTracker();
      // One very sharp card (400) sets the bar at 32: a 12 is bare table next to it.
      t.update([rect(40, 40, 200, 120), rect(250, 300, 200, 120)], [400, 12], width: w, height: h, now: at(0));
      expect(t.tracks.length, 1);
    });
  });

  group('a stuck or dropped card says why (log)', () {
    test('logs once after 5 s and when the track is dropped', () {
      final lines = <String>[];
      final old = sweepLog;
      sweepLog = lines.add;
      addTearDown(() => sweepLog = old);
      final t = SweepTracker();
      final card = rect(40, 60, 175, 100);
      // Moving the whole time: never steady.
      for (var i = 0; i <= 60; i++) {
        final n = at(i * 100);
        t.update([rect(40 + (i % 2) * 40.0, 60, 175, 100)], [100], width: w, height: h, now: n);
        t.next(width: w, height: h, now: n);
      }
      expect(lines.where((l) => l.contains('not captured after 5 s')).length, 1);
      t.update([], [], width: w, height: h, now: at(9000));
      expect(lines.any((l) => l.contains('dropped after')), isTrue);
      expect(card.area, greaterThan(0));
    });
  });

  group('repeat check (fifth sweep test: Millennium was "Already in queue" with no row)', () {
    img.Image blueCard(int seed) {
      // Dark blue cards with different printing: a light band at another place.
      final im = img.Image(width: 200, height: 120)..clear(img.ColorRgb8(10, 20, 70));
      img.fillRect(im, x1: 0, y1: 0, x2: 199, y2: 40, color: img.ColorRgb8(235, 235, 230));
      for (var i = 0; i < 6; i++) {
        final x = 10 + ((seed * 37 + i * 29) % 150);
        final y = 50 + ((seed * 13 + i * 17) % 55);
        img.fillRect(im, x1: x, y1: y, x2: x + 25, y2: y + 5, color: img.ColorRgb8(200, 200, 255));
      }
      return im;
    }

    test('two different dark blue cards are far apart; the same picture is identical', () {
      final a = dHash(Uint8List.fromList(img.encodeJpg(blueCard(1))));
      final b = dHash(Uint8List.fromList(img.encodeJpg(blueCard(2))));
      final a2 = dHash(Uint8List.fromList(img.encodeJpg(blueCard(1))));
      expect(hammingDistance(a, a2), 0);
      expect(hammingDistance(a, b), greaterThan(4), reason: 'the new 4-bit bar keeps them apart');
    });

    test('a repeat only counts while a row really exists', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final dir = await Directory.systemTemp.createTemp('ck_fifth');
      addTearDown(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
      final q = CardQueueRepository(db, ImageStore(dir));
      final id = await q.enqueue(side(['Steve Soto', 'Millennium Control Systems', 'steve@millennium.example']));
      expect(await q.anyLive([id]), isTrue);
      expect(await q.anyLive(const []), isFalse);
      await q.discard(id);
      expect(await q.anyLive([id]), isFalse, reason: 'removed from the queue: no longer a repeat');
    });

    test('a repeat gives its reason; sweep asks for a closer name', () async {
      final a = side(['Robert J. Pristas', 'Enpress LLC', 'robert@enpress.example']);
      final b = side(['Robert J Pristas', 'Enpress LLC', 'rjp@enpress.example']);
      expect(CardQueueRepository.sameCardWhy(a, b), 'name+company');
      final c = side(['Robert Prastas', 'Enpress LLC', 'rjp2@enpress.example']);
      expect(CardQueueRepository.sameCardWhy(a, c), 'name+company');
      expect(CardQueueRepository.sameCardWhy(a, c, nameBar: 0.99), isNull);
    });
  });

  group('garbled readings are retaken (fifth sweep test: "Viking Fof", "Improvin...")', () {
    test('no contact detail and no believable name is garbled', () {
      expect(isGarbled(side(['Improvin', 'AUTOMATI', 'MAX PAK'], conf: 0.3)), isTrue);
      expect(isGarbled(side(['Viking Fof', 'Epatwalshêviking'], conf: 0.3)), isTrue);
    });

    test('a weak name with a contact detail is garbled only when the still was blurry', () {
      final lines = ['Viking Fof', 'info@viking.example'];
      expect(isGarbled(side(lines, conf: 0.3)), isFalse);
      expect(isGarbled(side(lines, conf: 0.3, issues: const [QualityIssue.blurry])), isTrue);
    });

    test('a card with a phone, email or website is not', () {
      expect(isGarbled(side(['Dick Yisha', 'Maxpak', '330 485 6293'])), isFalse);
      expect(isGarbled(side(['Pyrotek', 'info@pyrotek.example'])), isFalse);
    });
  });
}
