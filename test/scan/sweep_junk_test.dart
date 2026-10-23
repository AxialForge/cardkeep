import 'dart:typed_data';

import 'package:card_organizer/parser/ocr.dart';
import 'package:card_organizer/scan/geometry.dart';
import 'package:card_organizer/scan/scan_pipeline.dart';
import 'package:card_organizer/scan/sweep_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

Quad box(double x, double y, double w, double h) => Quad([Pt(x, y), Pt(x + w, y), Pt(x + w, y + h), Pt(x, y + h)]);

/// Holds [q] steady long enough to be captured, then asks for the next card.
SweepTrack? held(SweepTracker tr, List<Quad> quads, List<double> sharp) {
  final t0 = DateTime(2026);
  for (var ms = 0; ms <= 1000; ms += 100) {
    tr.update(quads, sharp, width: 1000, height: 750, now: t0.add(Duration(milliseconds: ms)));
  }
  return tr.next(width: 1000, height: 750, now: t0.add(const Duration(milliseconds: 1000)));
}

ScannedSide side(List<String> lines) =>
    ScannedSide(hash: 'h', thumb: Uint8List(0), issues: const [], ocr: OcrPage.fromText(lines));

void main() {
  test('only card-shaped quads are captured; others are still outlined', () {
    expect(held(SweepTracker(), [box(100, 100, 350, 200)], [80]), isNotNull, reason: '3.5 x 2 in');
    expect(held(SweepTracker(), [box(100, 100, 340, 220)], [80]), isNotNull, reason: '85 x 55 mm');
    final square = SweepTracker();
    expect(held(square, [box(100, 100, 250, 250)], [80]), isNull, reason: 'square patch');
    expect(square.tracks, hasLength(1), reason: 'still outlined');
    expect(held(SweepTracker(), [box(100, 100, 600, 150)], [80]), isNull, reason: 'long strip (ruler, table edge)');
    expect(held(SweepTracker(), [box(10, 10, 950, 560)], [80]), isNull, reason: 'most of the frame');
  });

  test('a blank patch with no print is never captured, even held still', () {
    expect(held(SweepTracker(), [box(100, 100, 350, 200)], [1.5]), isNull);
    expect(
      held(SweepTracker(), [box(100, 100, 350, 200)], [15]),
      isNotNull,
      reason: 'soft but printed: after the wait',
    );
  });

  test('a quad on top of a done card is not captured again', () {
    final tr = SweepTracker();
    final first = held(tr, [box(100, 100, 350, 200)], [80])!;
    tr
      ..markReading(first.id)
      ..markDone(first.id);
    // The same card outlined again a little smaller (inner border), next to a new card.
    final t0 = DateTime(2027);
    for (var ms = 0; ms <= 1000; ms += 100) {
      tr.update(
        [box(100, 100, 350, 200), box(120, 115, 310, 175), box(550, 400, 350, 200)],
        [80, 80, 80],
        width: 1000,
        height: 750,
        now: t0.add(Duration(milliseconds: ms)),
      );
    }
    final next = tr.next(width: 1000, height: 750, now: t0.add(const Duration(milliseconds: 1000)));
    expect(next, isNotNull);
    expect(next!.quad.corners.first.x, 550, reason: 'the new card, not the inner outline of the done one');
  });

  test('"Not a card?" is shown, never retried, then forgotten', () {
    final tr = SweepTracker();
    final t = held(tr, [box(100, 100, 350, 200)], [80])!;
    final now = DateTime(2026, 1, 1, 0, 0, 1);
    tr
      ..markReading(t.id)
      ..markNotCard(t.id, now);
    expect(tr.byId(t.id)!.note, 'Not a card?');
    tr.update([box(100, 100, 350, 200)], [80], width: 1000, height: 750, now: now.add(const Duration(seconds: 1)));
    expect(tr.next(width: 1000, height: 750, now: now.add(const Duration(seconds: 1))), isNull);
    tr.update([box(100, 100, 350, 200)], [80], width: 1000, height: 750, now: now.add(const Duration(seconds: 2)));
    expect(tr.byId(t.id), isNull, reason: 'forgotten after the message');
  });

  test('a read with no name, company, phone, email or website is not a card', () {
    expect(hasAnyField(side(['', '*'])), isFalse);
    expect(hasAnyField(side(['Lena Hartmann', 'Purchasing Agent'])), isTrue);
    expect(hasAnyField(side(['330 555 0150'])), isTrue);
    expect(hasAnyField(side(['lena@cobalt.example'])), isTrue);
  });
}
