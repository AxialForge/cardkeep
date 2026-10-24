import 'dart:io';
import 'dart:typed_data';

import 'package:card_organizer/scan/card_detector.dart';
import 'package:card_organizer/scan/geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

Quad rect(double x, double y, double w, double h) => Quad([Pt(x, y), Pt(x + w, y), Pt(x + w, y + h), Pt(x, y + h)]);

void main() {
  const w = 480.0, h = 360.0, area = w * h;

  // Third recorded sweep: a card with a printed band or logo box inside it.
  test('a card keeps its outline when a printed box inside it is also detected', () {
    final card = rect(100, 100, 175, 100);
    final band = rect(120, 160, 60, 30); // the Millennium blue band / Maxpak logo box
    final out = mergeSweepQuads([band, card], area, width: w, height: h);
    expect(out, [same(card)]);
  });

  test('the Millennium card from the recording is found whole, not just its blue band', () {
    final img = image.decodeJpg(File('test/fixtures/sweep_millennium.jpg').readAsBytesSync())!;
    final gray = Uint8List.fromList([for (final p in img) p.luminance.toInt()]);
    final f = sweepDetect(GrayFrame(gray, img.width, img.height));
    // The card covers about a third of this frame; its band about a tenth.
    expect(f.cards.map((q) => q.area / (img.width * img.height)), contains(greaterThan(0.2)));
  });

  test('an outline around two cards is still dropped for the cards inside', () {
    final a = rect(60, 100, 160, 92), b = rect(240, 100, 160, 92);
    final both = rect(50, 90, 360, 205);
    final out = mergeSweepQuads([both, a, b], area, width: w, height: h);
    expect(out.toSet(), {a, b});
  });
}
