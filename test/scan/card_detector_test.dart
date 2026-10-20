import 'dart:typed_data';

import 'package:card_organizer/scan/card_detector.dart';
import 'package:card_organizer/scan/geometry.dart';
import 'package:card_organizer/scan/quality.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// A "photo": dark wood-ish table with light cards drawn as polygons, plus
/// text-like bars so sharpness has something to measure.
img.Image photo(List<List<img.Point>> cards, {int w = 1600, int h = 1200}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(70, 55, 45));
  for (final c in cards) {
    img.fillPolygon(im, vertices: c, color: img.ColorRgb8(238, 236, 230));
    final minX = c.map((p) => p.x).reduce((a, b) => a < b ? a : b).toInt();
    final minY = c.map((p) => p.y).reduce((a, b) => a < b ? a : b).toInt();
    final maxX = c.map((p) => p.x).reduce((a, b) => a > b ? a : b).toInt();
    final maxY = c.map((p) => p.y).reduce((a, b) => a > b ? a : b).toInt();
    final cw = maxX - minX, ch = maxY - minY;
    for (var i = 0; i < 6; i++) {
      final y = minY + ch * (0.25 + i * 0.1);
      img.fillRect(
        im,
        x1: minX + (cw * 0.2).round(),
        y1: y.round(),
        x2: minX + (cw * (0.5 + (i % 3) * 0.1)).round(),
        y2: (y + ch * 0.04).round(),
        color: img.ColorRgb8(30, 30, 35),
      );
    }
  }
  return im;
}

GrayFrame gray(img.Image im) {
  final g = img.grayscale(im.clone());
  final bytes = Uint8List(im.width * im.height);
  var i = 0;
  for (final p in g) {
    bytes[i++] = p.r.toInt();
  }
  return GrayFrame(bytes, im.width, im.height);
}

List<img.Point> pts(List<List<num>> xy) => [for (final p in xy) img.Point(p[0], p[1])];

void main() {
  // A US card (1.75:1) seen slightly from the side.
  final tilted = pts([
    [260, 300],
    [1340, 250],
    [1380, 900],
    [230, 870],
  ]);

  test('finds a tilted card and its corners', () {
    final d = detect(gray(photo([tilted])));
    expect(d.card, isNotNull);
    final q = d.card!;
    expect(q.tl.distanceTo(const Pt(260, 300)), lessThan(20));
    expect(q.br.distanceTo(const Pt(1380, 900)), lessThan(20));
    expect(d.metrics.sizeRatio, closeTo(0.93, 0.03)); // card long side ~1115 px / frame short side 1200
    expect(d.metrics.cardCutOff, isFalse);
    expect(d.issues, isNot(contains(QualityIssue.noCard)));
  });

  test('empty table: no card, hint asks to point at one', () {
    final d = detect(gray(photo([])));
    expect(d.card, isNull);
    expect(d.issues, [QualityIssue.noCard]);
  });

  test('a card far away is found but flagged "Move closer"', () {
    final d = detect(
      gray(
        photo([
          pts([
            [700, 500],
            [1050, 500],
            [1050, 700],
            [700, 700],
          ]),
        ]),
      ),
    );
    expect(d.card, isNotNull);
    expect(d.issues, contains(QualityIssue.tooSmall));
  });

  test('pile mode separates three cards', () {
    final d = detect(
      gray(
        photo([
          pts([
            [80, 100],
            [600, 100],
            [600, 400],
            [80, 400],
          ]),
          pts([
            [800, 120],
            [1500, 160],
            [1480, 560],
            [780, 520],
          ]),
          pts([
            [300, 700],
            [1000, 700],
            [1000, 1100],
            [300, 1100],
          ]),
        ]),
      ),
    );
    expect(d.cards, hasLength(3));
  });

  test('processStill rectifies to a flat card of at least 1400 px, original re-encoded', () {
    final jpeg = Uint8List.fromList(img.encodeJpg(photo([tilted]), quality: 95));
    final r = processStill(jpeg);
    expect(r.cards, hasLength(1));
    final card = r.cards.single;
    expect(card.manualCrop, isFalse);
    final rect = img.decodeJpg(card.jpeg)!;
    expect(rect.width, greaterThanOrEqualTo(Gates.minRectifiedLong));
    expect(rect.width / rect.height, closeTo(CardFormat.us.aspect, 0.02));
    expect(img.decodeJpg(card.thumbJpeg)!.width, 400);
    expect(img.decodeJpg(r.original)!.exif.isEmpty, isTrue);
  });

  test('processStill with no card keeps the whole photo and flags a manual crop', () {
    final r = processStill(Uint8List.fromList(img.encodeJpg(photo([]))));
    expect(r.cards.single.manualCrop, isTrue);
    expect(r.cards.single.issues, contains(QualityIssue.noCard));
  });

  test('manual corners skip detection', () {
    final r = processStill(
      Uint8List.fromList(img.encodeJpg(photo([tilted]))),
      corners: Quad([for (final p in tilted) Pt(p.x.toDouble(), p.y.toDouble())]),
    );
    expect(r.cards.single.manualCrop, isTrue);
    expect(img.decodeJpg(r.cards.single.jpeg)!.width, greaterThanOrEqualTo(1400));
  });

  test('OCR enhancement inverts dark cards', () {
    final dark = img.Image(width: 400, height: 230);
    img.fill(dark, color: img.ColorRgb8(20, 20, 25));
    final jpeg = Uint8List.fromList(img.encodeJpg(dark));
    expect(isDarkCard(jpeg), isTrue);
    final out = enhanceForOcr(jpeg, invert: true);
    final g = cv.imdecode(out, cv.IMREAD_GRAYSCALE);
    expect(cv.mean(g).val1, greaterThan(150));
    g.dispose();
  });
}
