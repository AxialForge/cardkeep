import 'dart:typed_data';

import 'package:card_organizer/scan/card_detector.dart';
import 'package:card_organizer/scan/geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('a sweep crop covers the tracked card with a margin, from a still at full size', () {
    // A 1200 x 1600 portrait still; the preview frame was 480 x 640 (same view).
    final still = img.Image(width: 1200, height: 1600)..clear(img.ColorRgb8(60, 60, 60));
    img.fillRect(still, x1: 300, y1: 400, x2: 737, y2: 650, color: img.ColorRgb8(245, 245, 240));
    final jpeg = Uint8List.fromList(img.encodeJpg(still));
    // The card in preview coordinates: 120..295 x 160..260 (= still / 2.5).
    final quad = Quad([const Pt(120, 160), const Pt(295, 160), const Pt(295, 260), const Pt(120, 260)]);
    final crop = img.decodeJpg(cropForSweep((jpeg, quad, 480, 640)))!;
    // The 437 x 250 px card warped flat with a 3% margin (second sweep test:
    // a wide margin took in the next card).
    expect(crop.width, inInclusiveRange(440, 470));
    expect(crop.height, inInclusiveRange(240, 275));
    // The card's middle is in the crop's middle.
    final mid = crop.getPixel(crop.width ~/ 2, crop.height ~/ 2);
    expect(mid.r, greaterThan(200));
  });

  test('a landscape still for a portrait preview is turned before cropping', () {
    final still = img.Image(width: 1600, height: 1200)..clear(img.ColorRgb8(60, 60, 60));
    final jpeg = Uint8List.fromList(img.encodeJpg(still));
    final quad = Quad([const Pt(100, 100), const Pt(300, 100), const Pt(300, 220), const Pt(100, 220)]);
    final crop = img.decodeJpg(cropForSweep((jpeg, quad, 480, 640)))!;
    expect(crop.width, greaterThan(crop.height), reason: 'the card is wide in the turned image');
  });
}
