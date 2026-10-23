import 'dart:typed_data';
import 'dart:ui';

import 'package:card_organizer/features/scan/reading_reveal.dart';
import 'package:card_organizer/parser/ocr.dart';
import 'package:card_organizer/scan/card_detector.dart';
import 'package:card_organizer/scan/geometry.dart';
import 'package:card_organizer/scan/quality.dart';
import 'package:card_organizer/scan/scan_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Fixes from the 0.6.2 phone test (docs/phone-tests/0.6.2-results.md).
void main() {
  ScannedSide side(List<OcrLine> lines, {List<String> qr = const []}) =>
      ScannedSide(hash: 'h', thumb: Uint8List(0), issues: const [], ocr: OcrPage(lines), qrRaw: qr);

  test('F16: a clearly read card (OCR ~0.8) is saved automatically', () {
    const c = 0.8;
    final s = side(const [
      OcrLine('Dana Reyes', top: 0, height: 30, confidence: c),
      OcrLine('Process Engineer', top: 40, height: 14, confidence: c),
      OcrLine('M 330 555 0142', top: 70, height: 12, confidence: c),
      OcrLine('dana.reyes@halden.example', top: 90, height: 12, confidence: c),
    ]);
    expect(isCleanCard(s), isTrue, reason: '${s.parsed?.name} ${s.parsed?.phones} ${s.check}');
  });

  test('F14: a QR code with a plain link fills an empty website', () {
    final s = side(const [OcrLine('Sam Ellery', height: 20), OcrLine('sam@orbit.example')], qr: ['https://orbit.example/sam']);
    expect(s.parsed?.website?.value, 'https://orbit.example/sam');
  });

  group('F6: field tags', () {
    test('a tag never covers another line of text', () {
      // Two stacked lines with no room on the right: the tag goes above or is left out.
      const a = Rect.fromLTWH(10, 40, 280, 14), b = Rect.fromLTWH(10, 56, 280, 14);
      final placed = placeLabels([a, b], {1: 'Phone'}, const Size(300, 200));
      for (final r in placed.values) {
        expect(r.overlaps(a), isFalse);
      }
      expect(placed[1]!.top, greaterThanOrEqualTo(b.bottom), reason: 'below b, since above it is a');
    });

    test('tags do not overlap each other and stay inside the card', () {
      final boxes = [for (var i = 0; i < 6; i++) Rect.fromLTWH(10, 10.0 + i * 16, 120, 14)];
      final placed = placeLabels(boxes, {for (var i = 0; i < 6; i++) i: 'Website'}, const Size(320, 140));
      final rs = placed.values.toList();
      for (var i = 0; i < rs.length; i++) {
        expect(const Rect.fromLTWH(0, 0, 320, 140).contains(rs[i].topLeft), isTrue);
        for (var j = i + 1; j < rs.length; j++) {
          expect(rs[i].overlaps(rs[j]), isFalse);
        }
      }
    });

    test('no tags on a small image', () {
      expect(placeLabels([const Rect.fromLTWH(0, 0, 50, 10)], {0: 'Name'}, const Size(200, 120)), isEmpty);
    });
  });

  test('F17: overlapping outlines of one card count once', () {
    final a = Quad([const Pt(0, 0), const Pt(100, 0), const Pt(100, 60), const Pt(0, 60)]);
    final b = Quad([const Pt(5, 50), const Pt(105, 50), const Pt(105, 110), const Pt(5, 110)]);
    final c = Quad([const Pt(4, 3), const Pt(104, 3), const Pt(104, 63), const Pt(4, 63)]);
    expect(overlapRatio(a, b), lessThan(0.3));
    expect(overlapRatio(a, c), greaterThan(0.9));
  });

  test('F35: a big photo is stored at 2000 px, well under 1 MB', () {
    final photo = img.Image(width: 4000, height: 3000)..clear(img.ColorRgb8(90, 90, 90));
    img.fillRect(photo, x1: 600, y1: 700, x2: 3400, y2: 2300, color: img.ColorRgb8(245, 245, 240));
    final r = processStill(Uint8List.fromList(img.encodeJpg(photo)));
    final stored = img.decodeJpg(r.original)!;
    expect(stored.width, originalLongEdge);
    expect(r.original.length, lessThan(1024 * 1024));
    expect(r.cards, isNotEmpty);
  });

  test('F23: no outline found -> the image is cut to the text', () {
    final plain = img.Image(width: 1600, height: 1200)..clear(img.ColorRgb8(240, 240, 240));
    final card = RectifiedCard(
      Uint8List.fromList(img.encodeJpg(plain)),
      Uint8List(0),
      Quad([const Pt(0, 0), const Pt(1599, 0), const Pt(1599, 1199), const Pt(0, 1199)]),
      const FrameMetrics(cardFound: false),
      manualCrop: true,
    );
    final cut = cropToText(card, [(600, 500, 300, 30), (600, 540, 260, 20)]);
    expect(cut, isNotNull);
    final out = img.decodeJpg(cut!.jpeg)!;
    expect(out.width, lessThan(800));
    expect(rotateCard(cut, 180).jpeg, isNotEmpty);
  });
}
