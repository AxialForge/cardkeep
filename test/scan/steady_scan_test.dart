import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:card_organizer/scan/card_detector.dart';
import 'package:card_organizer/scan/finger_quad.dart';
import 'package:card_organizer/scan/geometry.dart';
import 'package:card_organizer/scan/quad_smoother.dart';
import 'package:card_organizer/scan/quality.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv_dart.dart' as cv;

Quad quad(List<List<double>> xy) => Quad([for (final p in xy) Pt(p[0], p[1])]);

final card = quad([
  [100, 120],
  [420, 110],
  [430, 290],
  [95, 300],
]);

Quad shift(Quad q, double dx, double dy) => Quad([for (final p in q.corners) Pt(p.x + dx, p.y + dy)]);

DateTime t(int ms) => DateTime(2026, 10, 25, 12).add(Duration(milliseconds: ms));

double meanCornerError(Quad a, Quad b) {
  var s = 0.0;
  for (var i = 0; i < 4; i++) {
    s += a.corners[i].distanceTo(b.corners[i]);
  }
  return s / 4;
}

img.Image photo(List<img.Point> cardPoly, {int w = 1600, int h = 1200}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(60, 52, 48));
  img.fillPolygon(im, vertices: cardPoly, color: img.ColorRgb8(238, 236, 230));
  // Printed text-like bars so the card has content.
  final minX = cardPoly.map((p) => p.x).reduce(math.min).toInt(),
      minY = cardPoly.map((p) => p.y).reduce(math.min).toInt();
  for (var i = 0; i < 6; i++) {
    img.fillRect(
      im,
      x1: minX + 260,
      y1: minY + 160 + i * 70,
      x2: minX + 700,
      y2: minY + 190 + i * 70,
      color: img.ColorRgb8(30, 30, 35),
    );
  }
  return im;
}

Uint8List grayBytes(img.Image im) {
  final g = img.grayscale(im.clone());
  final bytes = Uint8List(im.width * im.height);
  var i = 0;
  for (final p in g) {
    bytes[i++] = p.r.toInt();
  }
  return bytes;
}

/// 0/255 mask of the pixels that are skin-coloured in [im].
Uint8List skinBytes(img.Image im) {
  final out = Uint8List(im.width * im.height);
  var i = 0;
  for (final p in im) {
    final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
    final y = 0.299 * r + 0.587 * g + 0.114 * b;
    final cr = 128 + 0.713 * (r - y), cb = 128 + 0.564 * (b - y);
    out[i++] = isSkinYCrCb(y.round(), cb.round(), cr.round()) ? 255 : 0;
  }
  return out;
}

void main() {
  group('QuadSmoother', () {
    test('jitter of a few pixels is smoothed to well under the raw noise', () {
      final s = QuadSmoother();
      final rnd = math.Random(7);
      var worstRaw = 0.0, worstShown = 0.0;
      SmoothedQuad? last;
      for (var i = 0; i < 40; i++) {
        final noisy = shift(card, (rnd.nextDouble() - 0.5) * 16, (rnd.nextDouble() - 0.5) * 16);
        last = s.update(noisy, now: t(i * 100), frameWidth: 480);
        if (i >= 10) {
          worstRaw = math.max(worstRaw, meanCornerError(noisy, card));
          worstShown = math.max(worstShown, meanCornerError(last!.quad, card));
        }
      }
      expect(worstShown, lessThan(worstRaw * 0.75));
      expect(last!.steady, isTrue, reason: 'hand jitter must not restart the capture timer');
      expect(last.held, isFalse);
    });

    test('a missed detection is held for 600 ms, fading, then gone', () {
      final s = QuadSmoother();
      for (var i = 0; i < 5; i++) {
        expect(s.update(card, now: t(i * 100), frameWidth: 480), isNotNull);
      }
      final a = s.update(null, now: t(500), frameWidth: 480)!;
      final b = s.update(null, now: t(800), frameWidth: 480)!;
      expect(a.held, isTrue);
      expect(b.held, isTrue);
      expect(b.opacity, lessThan(a.opacity));
      expect(b.opacity, greaterThan(0.3));
      expect(meanCornerError(b.quad, card), lessThan(1));
      expect(s.update(null, now: t(1200), frameWidth: 480), isNull, reason: 'the hold has run out');
      expect(s.shown, isNull);
    });

    test('a detection that returns after a drop-out is blended, not jumped to', () {
      final s = QuadSmoother();
      for (var i = 0; i < 5; i++) {
        s.update(card, now: t(i * 100), frameWidth: 480);
      }
      s.update(null, now: t(500), frameWidth: 480);
      final back = s.update(shift(card, 10, 0), now: t(600), frameWidth: 480)!;
      expect(back.held, isFalse);
      expect(back.opacity, 1);
      expect(back.quad.tl.x, closeTo(card.tl.x + 3.5, 1.0)); // 35% of the way
    });

    test('a far-off detection is only taken once a second frame agrees', () {
      final s = QuadSmoother();
      for (var i = 0; i < 6; i++) {
        s.update(card, now: t(i * 100), frameWidth: 480);
      }
      final elsewhere = shift(card, 180, 150);
      final first = s.update(elsewhere, now: t(600), frameWidth: 480)!;
      expect(meanCornerError(first.quad, card), lessThan(1), reason: 'one odd frame does not move the outline');
      expect(first.held, isTrue);
      final second = s.update(elsewhere, now: t(700), frameWidth: 480)!;
      expect(meanCornerError(second.quad, elsewhere), lessThan(1), reason: 'confirmed by a second frame');
      expect(second.held, isFalse);
    });

    test('a lone far-off frame never replaces the card, and the old one fades if it stays', () {
      final s = QuadSmoother();
      for (var i = 0; i < 6; i++) {
        s.update(card, now: t(i * 100), frameWidth: 480);
      }
      s.update(shift(card, 200, 100), now: t(600), frameWidth: 480);
      final back = s.update(card, now: t(700), frameWidth: 480)!;
      expect(meanCornerError(back.quad, card), lessThan(1));
      expect(back.held, isFalse);
    });

    test('moving the card is not steady, holding it is', () {
      final s = QuadSmoother();
      var moving = true;
      for (var i = 0; i < 8; i++) {
        final r = s.update(shift(card, i * 14.0, 0), now: t(i * 100), frameWidth: 480)!;
        if (i > 2) moving = moving && !r.steady;
      }
      expect(moving, isTrue);
      SmoothedQuad? r;
      for (var i = 0; i < 12; i++) {
        r = s.update(shift(card, 98, 0), now: t(1000 + i * 100), frameWidth: 480);
      }
      expect(r!.steady, isTrue);
    });
  });

  group('glare', () {
    img.Image glossy({List<List<int>> spots = const []}) {
      final im = photo([img.Point(260, 300), img.Point(1340, 250), img.Point(1380, 900), img.Point(230, 870)]);
      for (final s in spots) {
        img.fillRect(im, x1: s[0], y1: s[1], x2: s[2], y2: s[3], color: img.ColorRgb8(255, 255, 255));
      }
      return im;
    }

    Detection run(img.Image im) => detect(GrayFrame(grayBytes(im), im.width, im.height));

    test('small specular spots are clipped but do not count as glare', () {
      final d = run(
        glossy(
          spots: [
            [400, 400, 520, 480],
            [900, 600, 1000, 680],
            [600, 750, 700, 820],
          ],
        ),
      );
      expect(d.card, isNotNull);
      expect(d.metrics.specular, greaterThan(0.005));
      expect(d.metrics.glare, 0);
      expect(d.issues, isNot(contains(QualityIssue.glare)));
    });

    test('a plain white card (not clipped) is no glare at all', () {
      final d = run(glossy());
      expect(d.metrics.glare, 0);
      expect(d.metrics.specular, lessThan(0.02));
    });

    test('a card mostly blown out is glare', () {
      final d = run(
        glossy(
          spots: [
            [250, 250, 1400, 640],
          ],
        ),
      );
      expect(d.card, isNotNull);
      expect(d.metrics.glare, greaterThanOrEqualTo(Gates.maxGlare));
      expect(d.issues, contains(QualityIssue.glare));
    });

    test('glare is a soft issue: the shutter still fires on its own', () {
      final a = AutoCapture();
      const glare = [QualityIssue.glare];
      expect(a.update(issues: glare, steady: true, now: t(0)), isFalse);
      expect(a.update(issues: glare, steady: true, now: t(Gates.softCaptureMs - 50)), isFalse);
      expect(a.update(issues: glare, steady: true, now: t(Gates.softCaptureMs + 10)), isTrue);
    });

    test('the best of a burst is the one with the least blown-out card', () {
      Uint8List jpeg(img.Image im) => Uint8List.fromList(img.encodeJpg(im, quality: 90));
      final clean = jpeg(glossy());
      final washed = jpeg(
        glossy(
          spots: [
            [250, 250, 1400, 640],
          ],
        ),
      );
      final spotted = jpeg(
        glossy(
          spots: [
            [400, 400, 700, 600],
            [900, 600, 1200, 800],
          ],
        ),
      );
      expect(pickBestStill([washed, spotted, clean]), 2);
      expect(pickBestStill([washed, clean, spotted]), 1);
      expect(pickBestStill([spotted, washed]), 0);
    });
  });

  group('finger on the card', () {
    final truth = quad([
      [260, 300],
      [1340, 250],
      [1380, 900],
      [230, 870],
    ]);

    img.Image held({required List<img.Point> finger}) {
      final im = photo([img.Point(260, 300), img.Point(1340, 250), img.Point(1380, 900), img.Point(230, 870)]);
      img.fillPolygon(im, vertices: finger, color: img.ColorRgb8(205, 150, 118));
      return im;
    }

    Detection run(img.Image im, {bool withSkin = true}) =>
        detect(GrayFrame(grayBytes(im), im.width, im.height, skin: withSkin ? skinBytes(im) : null));

    void expectNear(Detection d) {
      expect(d.card, isNotNull, reason: 'the card must be found with the finger on it');
      final err = meanCornerError(d.card!, truth);
      expect(err, lessThan(0.06 * truth.longSide), reason: 'outline off by $err px: ${d.card}');
    }

    test('a thumb over a corner: the hidden corner is completed from the visible edges', () {
      final d = run(
        held(finger: [img.Point(1180, 120), img.Point(1480, 120), img.Point(1480, 420), img.Point(1180, 420)]),
      );
      expectNear(d);
    });

    test('a thumb over part of an edge', () {
      final d = run(held(finger: [img.Point(560, 200), img.Point(900, 200), img.Point(900, 400), img.Point(560, 400)]));
      expectNear(d);
    });

    test('a finger at the side, over the card edge, as the card is usually held', () {
      final d = run(held(finger: [img.Point(100, 520), img.Point(400, 520), img.Point(400, 700), img.Point(100, 700)]));
      expectNear(d);
    });

    test('without a finger the skin mask changes nothing', () {
      final im = photo([img.Point(260, 300), img.Point(1340, 250), img.Point(1380, 900), img.Point(230, 870)]);
      final a = detect(GrayFrame(grayBytes(im), im.width, im.height));
      final b = detect(GrayFrame(grayBytes(im), im.width, im.height, skin: skinBytes(im)));
      expect(b.completed, isFalse);
      expect(meanCornerError(a.card!, b.card!), lessThan(1));
    });

    test('cream-coloured card stock is not mistaken for skin', () {
      final im = img.Image(width: 8, height: 8);
      img.fill(im, color: img.ColorRgb8(245, 235, 215));
      expect(skinBytes(im).every((v) => v == 0), isTrue);
    });
  });

  group('real frame: business card held by a thumb', () {
    // Hand-measured corners in the 720 x 830 fixture (the top-left corner is
    // behind the thumb).
    final truth = quad([
      [142, 428],
      [519, 286],
      [593, 505],
      [213, 635],
    ]);

    test('found with the thumb on it, within a few percent of the true corners', () {
      final color = cv.imdecode(File('test/fixtures/card_held_by_thumb.jpg').readAsBytesSync(), cv.IMREAD_COLOR);
      final gray = cv.cvtColor(color, cv.COLOR_BGR2GRAY);
      final skin = skinMaskBgr(color);
      final d = detect(
        GrayFrame(Uint8List.fromList(gray.data), gray.cols, gray.rows, skin: Uint8List.fromList(skin.data)),
      );
      color.dispose();
      gray.dispose();
      skin.dispose();
      expect(d.card, isNotNull, reason: 'the card held by a thumb was not found');
      final err = meanCornerError(d.card!, truth);
      expect(err, lessThan(0.12 * truth.longSide), reason: 'outline off by $err px: ${d.card}');
    });
  });
}
