// Third Sweep test on the S25 Ultra (0.7.2): cards are read from a full
// still, cut loosely with their neighbours painted out, and the turn that reads
// like words wins.
import 'dart:typed_data';

import 'package:card_organizer/parser/ocr.dart';
import 'package:card_organizer/scan/card_detector.dart';
import 'package:card_organizer/scan/geometry.dart';
import 'package:card_organizer/scan/scan_pipeline.dart';
import 'package:card_organizer/scan/sweep_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

Quad rect(double l, double t, double r, double b) => Quad([Pt(l, t), Pt(r, t), Pt(r, b), Pt(l, b)]);

/// A portrait still (1200 x 1600) of a dark table with two printed cards.
Uint8List still() {
  final m = cv.Mat.zeros(1600, 1200, cv.MatType.CV_8UC3);
  m.setTo(cv.Scalar(40, 40, 40, 0));
  for (final (l, t) in [(150, 300), (650, 300)]) {
    cv.rectangle(m, cv.Rect(l, t, 420, 240), cv.Scalar(235, 235, 235, 0), thickness: -1);
    for (var i = 0; i < 4; i++) {
      cv.putText(
        m,
        'Card line $i',
        cv.Point(l + 20, t + 50 + i * 45),
        cv.FONT_HERSHEY_SIMPLEX,
        0.9,
        cv.Scalar(20, 20, 20, 0),
        thickness: 2,
      );
    }
  }
  final (_, jpg) = cv.imencode('.jpg', m);
  m.dispose();
  return jpg;
}

void main() {
  test('preview quads map into the still, centred when the shapes differ', () {
    final same = mapPreviewToStill(rect(10, 20, 110, 80), 300, 400, 1200, 1600);
    expect(same.corners.first.x, closeTo(40, 0.01));
    expect(same.corners.first.y, closeTo(80, 0.01));
    // A 9:16 preview over a 3:4 still shows its middle: same height, centred.
    final wide = mapPreviewToStill(rect(0, 0, 90, 160), 90, 160, 1200, 1600);
    expect(wide.corners.first.y, closeTo(0, 0.01));
    expect(wide.corners.first.x, closeTo((1200 - 900) / 2, 0.01));
  });

  test('a still crop keeps a margin, paints the neighbour out, and the card is found in it', () {
    // Preview 300 x 400: the still is 4x.
    final target = rect(150 / 4, 300 / 4, 570 / 4, 540 / 4);
    final neighbour = rect(650 / 4, 300 / 4, 1070 / 4, 540 / 4);
    final cut = cropStillForSweep((still(), target, [neighbour], 300, 400));
    final img = cv.imdecode(cut.jpeg, cv.IMREAD_GRAYSCALE);
    // 10% margin each side of a 420 x 240 card.
    expect(img.cols, greaterThan(440));
    expect(img.rows, greaterThan(250));
    // Where the neighbour would start inside the crop is table colour now.
    final x = 650 - cut.source.dx + 5, y = 400 - cut.source.dy;
    if (x < img.cols) expect(img.at<int>(y, x), lessThan(90));
    img.dispose();
    expect(cut.sharpness, greaterThan(0));

    final r = processStill(cut.jpeg, fallback: cut.fallback, source: cut.source);
    expect(r.cards, hasLength(1));
    final card = r.cards.single;
    expect(card.manualCrop, isFalse);
    // The card sits well inside the still, so it is not cut off.
    expect(card.metrics.cardCutOff, isFalse);
  });

  test('when the edge search finds nothing, the tracked outline is used', () {
    final blank = cv.Mat.zeros(300, 500, cv.MatType.CV_8UC3)..setTo(cv.Scalar(120, 120, 120, 0));
    final (_, jpg) = cv.imencode('.jpg', blank);
    blank.dispose();
    final r = processStill(
      jpg,
      fallback: rect(50, 40, 450, 260),
      source: (dx: 300, dy: 300, width: 1200, height: 1600),
    );
    expect(r.cards.single.manualCrop, isFalse);
    expect(r.cards.single.quad.corners.first.x, closeTo(50, 0.01));
  });

  test('an upside-down reading of garbage loses to the upright words', () {
    final upright = OcrPage.fromText(['Pyrotek', 'Veronica Vecchio', 'HR Business Partner', 'Pyrotek Inc.']);
    final flipped = OcrPage.fromText(['ʞǝʇoɹʎԀ', 'oiqɔɔǝΛ', 'yrotek', 'aJtuBd Ssauisn', 'xI']);
    expect(wordQuality(upright), greaterThan(wordQuality(flipped)));
    expect(bestRotation({0: orientationScore(flipped), 180: orientationScore(upright)}), 180);
  });

  test('no still is taken while the whole view is still moving', () {
    final t = SweepTracker();
    final start = DateTime(2026);
    // A card sliding 40 px per 100 ms across a 480 px frame: fast.
    for (var i = 0; i < 6; i++) {
      t.update(
        [rect(40.0 + i * 40, 100, 200.0 + i * 40, 190)],
        [80],
        width: 360,
        height: 480,
        now: start.add(Duration(milliseconds: i * 100)),
      );
    }
    expect(t.viewMotion(480), greaterThan(t.maxViewMotion));
    expect(t.next(width: 360, height: 480, now: start.add(const Duration(milliseconds: 500))), isNull);
  });
}
