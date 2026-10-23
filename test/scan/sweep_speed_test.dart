import 'dart:math' as math;
import 'dart:typed_data';

import 'package:card_organizer/scan/card_detector.dart';
import 'package:card_organizer/scan/geometry.dart';
import 'package:card_organizer/scan/sweep_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A card-shaped quad (3.5 x 2) with its top-left at (x, y) and width [cw].
Quad card(double x, double y, [double cw = 175]) {
  final ch = cw * 2 / 3.5;
  return Quad([Pt(x, y), Pt(x + cw, y), Pt(x + cw, y + ch), Pt(x, y + ch)]);
}

/// A dark table with [n] light cards laid out in a grid, as the screen's
/// detector sees it: a 1440 x 1080 preview subsampled to 360 x 480 portrait.
GrayFrame table(int n, {int w = 360, int h = 480}) {
  final rnd = math.Random(7);
  final px = Uint8List(w * h);
  for (var i = 0; i < px.length; i++) {
    px[i] = 40 + rnd.nextInt(20);
  }
  const cw = 100, ch = 57;
  for (var k = 0; k < n; k++) {
    final x0 = 20 + (k % 3) * 115, y0 = 30 + (k ~/ 3) * 90;
    for (var y = y0; y < y0 + ch; y++) {
      for (var x = x0; x < x0 + cw; x++) {
        px[y * w + x] = 225 + rnd.nextInt(20);
      }
    }
    // A little "text" so the card has some detail.
    for (var y = y0 + 15; y < y0 + 19; y++) {
      for (var x = x0 + 10; x < x0 + 70; x++) {
        px[y * w + x] = 30;
      }
    }
  }
  return GrayFrame(px, w, h);
}

void main() {
  group('motion estimate', () {
    test('the median ignores one wrongly matched card', () {
      final s = medianShift([
        (const Pt(0, 0), const Pt(10, -4)),
        (const Pt(100, 100), const Pt(111, 95)),
        (const Pt(200, 50), const Pt(209, 47)),
        (const Pt(300, 300), const Pt(200, 400)), // a mismatch
      ])!;
      expect(s.x, closeTo(9.5, 0.01));
      expect(s.y, closeTo(-3.5, 0.01));
      expect(medianShift([]), isNull);
    });

    test('outlines glide with the view between analysed frames, and fade once out of view', () {
      final tr = SweepTracker();
      final t0 = DateTime(2026, 10, 23, 12);
      DateTime at(int ms) => t0.add(Duration(milliseconds: ms));
      tr.update([card(40, 60), card(260, 300)], [100, 100], width: 480, height: 640, now: at(0));
      // Everything moved 20 px right in 100 ms.
      tr.update([card(60, 60), card(280, 300)], [100, 100], width: 480, height: 640, now: at(100));
      expect(tr.velocity.x, closeTo(0.12, 0.001), reason: 'smoothed: 60% of 0.2 px/ms');
      final t = tr.tracks.first;
      final ahead = tr.displayQuad(t, at(200));
      expect(ahead.corners.first.x - t.quad.corners.first.x, closeTo(12, 0.5));
      expect(tr.displayQuad(t, at(100)).corners.first.x, t.quad.corners.first.x, reason: 'no lag right after a frame');
      // Capped: a long gap never carries an outline far away.
      expect(tr.displayQuad(t, at(5000)).corners.first.x - t.quad.corners.first.x, closeTo(48, 0.5));
      expect(tr.opacity(t, at(300)), 1);
      expect(tr.opacity(t, at(850)), closeTo(0.5, 0.1));
      expect(tr.opacity(t, at(1300)), 0);
    });

    test('with no matches the drift dies down', () {
      final tr = SweepTracker();
      final t0 = DateTime(2026, 10, 23, 12);
      tr.update([card(40, 60)], [100], width: 480, height: 640, now: t0);
      tr.update([card(60, 60)], [100], width: 480, height: 640, now: t0.add(const Duration(milliseconds: 100)));
      final v = tr.velocity.x;
      tr.update([], [], width: 480, height: 640, now: t0.add(const Duration(milliseconds: 200)));
      expect(tr.velocity.x, closeTo(v / 2, 0.001));
    });
  });

  group('quad merging', () {
    test('IoU of boxes', () {
      expect(iou(card(0, 0), card(0, 0)), closeTo(1, 1e-9));
      expect(iou(card(0, 0), card(500, 500)), 0);
      expect(iou(card(0, 0), card(87.5, 0)), closeTo(1 / 3, 0.01));
    });

    test('two outlines of one card become one; separate cards stay apart', () {
      final merged = mergeSweepQuads([card(40, 60), card(43, 62), card(260, 300)], 480 * 640);
      expect(merged.length, 2);
    });

    test('small cards in a wide shot are kept, up to 12', () {
      final many = [for (var k = 0; k < 15; k++) card(10 + (k % 5) * 92.0, 10 + (k ~/ 5) * 120.0, 60)];
      // 60 x 34 px in a 480 x 640 frame is 0.7% of it: kept.
      expect(mergeSweepQuads(many, 480 * 640).length, sweepMaxCards);
    });
  });

  test('preview crop: only the card, turned to portrait, in colour', () {
    // A 640 x 480 sensor frame (landscape), shown portrait with a 90° turn:
    // portrait (px, py) <- sensor (py, 479 - px).
    const sw = 640, sh = 480;
    final y = Uint8List(sw * sh)..fillRange(0, sw * sh, 50);
    final u = Uint8List(sw * sh ~/ 2)..fillRange(0, sw * sh ~/ 2, 128);
    final v = Uint8List(sw * sh ~/ 2)..fillRange(0, sw * sh ~/ 2, 128);
    // A white card at portrait x 100..300, y 200..314 (sensor x 200..314, y 179..379).
    for (var iy = 179; iy < 380; iy++) {
      for (var ix = 200; ix < 315; ix++) {
        y[iy * sw + ix] = 240;
      }
    }
    final frame = YuvFrame(
      y,
      u,
      v,
      width: sw,
      height: sh,
      yRowStride: sw,
      uvRowStride: sw,
      uvPixelStride: 2,
      sensorOrientation: 90,
    );
    // Detection frame = portrait 480 x 640 at full size here.
    final quad = Quad([const Pt(100, 200), const Pt(300, 200), const Pt(300, 314), const Pt(100, 314)]);
    final crop = img.decodeJpg(cropYuvForSweep((frame, quad, 480, 640)))!;
    // The card warped flat along its outline with a 3% margin: only the card.
    expect(crop.width, inInclusiveRange(200, 214), reason: '200 px card + 3% margin');
    expect(crop.height, inInclusiveRange(110, 125));
    expect(crop.getPixel(crop.width ~/ 2, crop.height ~/ 2).r, greaterThan(200));
    expect(crop.getPixel(crop.width ~/ 4, crop.height ~/ 4).r, greaterThan(200), reason: 'no table inside the card');
  });

  test('detection speed on a preview-sized frame (benchmark, PC)', () {
    final f = table(6);
    final first = sweepDetect(f);
    expect(first.cards.length, 6, reason: 'every card on the table is found');
    final watch = Stopwatch()..start();
    const runs = 30;
    for (var i = 0; i < runs; i++) {
      sweepDetect(f);
    }
    final ms = watch.elapsedMicroseconds / runs / 1000;
    // ignore: avoid_print
    print('sweepDetect: ${ms.toStringAsFixed(1)} ms per 360x480 frame (6 cards)');
    expect(ms, lessThan(60));
  });
}
