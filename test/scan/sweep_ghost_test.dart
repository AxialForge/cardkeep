// Fourth Sweep test: a ghost quad over a card must not erase part of it, and a
// half-flat cut is not queued.
import 'dart:typed_data';

import 'package:card_organizer/scan/card_detector.dart';
import 'package:card_organizer/scan/geometry.dart';
import 'package:card_organizer/scan/sweep_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

Quad rect(double l, double t, double r, double b) => Quad([Pt(l, t), Pt(r, t), Pt(r, b), Pt(l, b)]);

/// 1200 x 1600 dark still with one bright printed card at (300,500) 600 x 340.
Uint8List still() {
  final m = cv.Mat.zeros(1600, 1200, cv.MatType.CV_8UC3)..setTo(cv.Scalar(40, 40, 40, 0));
  cv.rectangle(m, cv.Rect(300, 500, 600, 340), cv.Scalar(235, 235, 235, 0), thickness: -1);
  for (var i = 0; i < 5; i++) {
    cv.putText(
      m,
      'Card text $i',
      cv.Point(330, 560 + i * 55),
      cv.FONT_HERSHEY_SIMPLEX,
      1.1,
      cv.Scalar(20, 20, 20, 0),
      thickness: 3,
    );
  }
  final (_, jpg) = cv.imencode('.jpg', m);
  m.dispose();
  return jpg;
}

int grey(Uint8List jpeg, int x, int y) {
  final g = cv.imdecode(jpeg, cv.IMREAD_GRAYSCALE);
  final v = g.at<int>(y, x);
  g.dispose();
  return v;
}

void main() {
  // Preview 300 x 400: the still is 4x.
  final target = rect(75, 125, 225, 210);

  test('a small ghost outline over the card is never painted onto it', () {
    final ghost = rect(120, 140, 160, 170); // ~6% of the card, inside it
    expect(sweepMaskable(target, [ghost], width: 300, height: 400), isEmpty);
    final cut = cropStillForSweep((still(), target, [ghost], 300, 400));
    expect(cut.ok, isTrue);
    expect(cut.flat, lessThan(0.2));
    // The card's pale body is intact where the ghost sat (inside the card).
    final x = 560 - cut.source.dx, y = 520 - cut.source.dy;
    expect(grey(cut.jpeg, x, y), greaterThan(180));
  });

  test('a card-sized neighbour that overlaps the card is not painted either', () {
    final overlapper = rect(120, 125, 270, 210); // half on the target
    expect(sweepMaskable(target, [overlapper], width: 300, height: 400), isEmpty);
    final neighbour = rect(10, 300, 160, 385); // far away, card-sized
    expect(sweepMaskable(target, [neighbour], width: 300, height: 400), [neighbour]);
  });

  test('a crop that is mostly flat table colour is not ok', () {
    final blank = cv.Mat.zeros(1600, 1200, cv.MatType.CV_8UC3)..setTo(cv.Scalar(40, 40, 40, 0));
    final (_, jpg) = cv.imencode('.jpg', blank);
    blank.dispose();
    final cut = cropStillForSweep((jpg, target, const [], 300, 400));
    expect(cut.flat, greaterThan(sweepMaxFlat));
    expect(cut.ok, isFalse);
  });

  test('stray small outlines beside real cards are dropped, a lone small card stays', () {
    final t = SweepTracker();
    final now = DateTime(2026, 10, 24, 9);
    final cards = [rect(20, 20, 140, 100), rect(160, 20, 280, 100), rect(20, 200, 140, 280)];
    final ghost = rect(200, 300, 215, 312); // far under 25% of a card and 3% of the view
    t.update([...cards, ghost], const [30, 30, 30, 30], width: 300, height: 400, now: now);
    expect(t.tracks, hasLength(3));
    final solo = SweepTracker();
    solo.update([rect(100, 100, 130, 120)], const [30], width: 300, height: 400, now: now);
    expect(solo.tracks, hasLength(1));
  });
}
