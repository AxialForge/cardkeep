import 'dart:io';
import 'dart:typed_data';

import 'package:card_organizer/core/images/image_store.dart';
import 'package:card_organizer/scan/geometry.dart';
import 'package:card_organizer/scan/quality.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Quad rect(double x, double y, double w, double h) =>
    Quad([Pt(x + w, y + h), Pt(x, y), Pt(x + w, y), Pt(x, y + h)]); // deliberately shuffled

void main() {
  group('Quad', () {
    test('orders corners TL, TR, BR, BL from any order', () {
      final q = rect(10, 20, 350, 200);
      expect([q.tl.x, q.tl.y, q.tr.x, q.br.y, q.bl.x], [10, 20, 360, 220, 10]);
      expect(q.area, 70000);
      expect(q.aspect, closeTo(1.75, 1e-9));
      expect(q.isConvex, isTrue);
      expect(q.isPortrait, isFalse);
    });

    test('a dented outline is not convex', () {
      // TL, TR, BR, BL after ordering, with BR pushed inside the shape.
      expect(Quad([const Pt(0, 0), const Pt(300, 0), const Pt(120, 90), const Pt(0, 200)]).isConvex, isFalse);
    });

    test('aspect matching knows US, EU and Japanese cards, either way up', () {
      expect(bestAspect(1.75).format, CardFormat.us);
      expect(bestAspect(1.55).format, CardFormat.eu);
      expect(bestAspect(1.66).format, CardFormat.japan);
      expect(rect(0, 0, 200, 350).isPortrait, isTrue);
      expect(bestAspect(rect(0, 0, 200, 350).aspect).format, CardFormat.us);
    });
  });

  group('pickCardQuad', () {
    const frame = 1000.0 * 750;
    test('prefers the biggest card-shaped outline', () {
      final small = rect(0, 0, 175, 100);
      final big = rect(100, 100, 700, 400);
      final square = rect(0, 0, 600, 600);
      expect(pickCardQuad([small, square, big], frameArea: frame), same(big));
    });
    test('ignores the whole frame, slivers and squares', () {
      expect(pickCardQuad([rect(0, 0, 1000, 750)], frameArea: frame), isNull);
      expect(pickCardQuad([rect(0, 0, 60, 34)], frameArea: frame), isNull);
      expect(pickCardQuad([rect(0, 0, 500, 500)], frameArea: frame), isNull);
    });
  });

  test('rectified size keeps the card aspect and at least 1400 px', () {
    final s = rectifiedSize(rect(0, 0, 700, 400));
    expect(s.width, 1400);
    expect(s.height, 800);
    final p = rectifiedSize(rect(0, 0, 1200, 2100));
    expect(p.height, 2000);
    expect(p.width, (2000 / 1.75).round());
  });

  test('sameQuad uses a per-corner tolerance', () {
    expect(sameQuad(rect(0, 0, 350, 200), rect(3, 2, 350, 200), 5), isTrue);
    expect(sameQuad(rect(0, 0, 350, 200), rect(20, 0, 350, 200), 5), isFalse);
  });

  group('quality gates', () {
    test('a clean frame has no issues', () {
      expect(
        assess(
          const FrameMetrics(cardFound: true, areaRatio: 0.6, sharpness: 150, glare: 0.002, highlight: 240, shadow: 30),
        ),
        isEmpty,
      );
    });
    test('issues come out in hint priority order', () {
      final issues = assess(
        const FrameMetrics(
          cardFound: true,
          cardCutOff: true,
          areaRatio: 0.2,
          sharpness: 20,
          glare: 0.05,
          highlight: 60,
          shadow: 10,
        ),
      );
      expect(issues, [
        QualityIssue.cutOff,
        QualityIssue.tooSmall,
        QualityIssue.blurry,
        QualityIssue.glare,
        QualityIssue.dark,
      ]);
      expect(issues.first.hint, 'Card cut off');
    });
    test('white and black cards are both fine; only washed-out or dim ones are flagged', () {
      const white = FrameMetrics(cardFound: true, areaRatio: 0.6, highlight: 252, shadow: 40);
      const black = FrameMetrics(cardFound: true, areaRatio: 0.6, highlight: 235, shadow: 12);
      const washed = FrameMetrics(cardFound: true, areaRatio: 0.6, highlight: 255, shadow: 240);
      const dim = FrameMetrics(cardFound: true, areaRatio: 0.6, highlight: 70, shadow: 5);
      expect(assess(white), isEmpty);
      expect(assess(black), isEmpty);
      expect(assess(washed), [QualityIssue.bright]);
      expect(assess(dim), [QualityIssue.dark]);
    });
    test('no card short-circuits', () {
      expect(assess(const FrameMetrics(cardFound: false)), [QualityIssue.noCard]);
    });
  });

  test('auto-capture fires once after 400 ms of a clean, steady card', () {
    final a = AutoCapture();
    final t0 = DateTime(2026);
    expect(a.update(clean: true, steady: true, now: t0), isFalse);
    expect(a.update(clean: true, steady: true, now: t0.add(const Duration(milliseconds: 200))), isFalse);
    expect(a.update(clean: false, steady: true, now: t0.add(const Duration(milliseconds: 300))), isFalse);
    // Restarted by the unclean frame.
    expect(a.update(clean: true, steady: true, now: t0.add(const Duration(milliseconds: 500))), isFalse);
    expect(a.update(clean: true, steady: true, now: t0.add(const Duration(milliseconds: 950))), isTrue);
    expect(a.update(clean: true, steady: true, now: t0.add(const Duration(milliseconds: 1200))), isFalse);
    a.reset();
    expect(a.update(clean: true, steady: true, now: t0), isFalse);
  });

  test('image store: hash naming, pending cleanup, idempotent', () async {
    final dir = await Directory.systemTemp.createTemp('ck_store');
    addTearDown(() => dir.delete(recursive: true));
    final store = ImageStore(dir);
    final original = Uint8List.fromList(img.encodeJpg(img.Image(width: 160, height: 120)));
    final rectified = Uint8List.fromList(img.encodeJpg(img.Image(width: 140, height: 80)));
    final thumb = Uint8List.fromList(img.encodeJpg(img.Image(width: 40, height: 23)));

    final pending = await store.savePending(original);
    expect(store.orphanedPending(), hasLength(1));
    final h = await store.commit(originalJpeg: original, rectifiedJpeg: rectified, thumbJpeg: thumb, pending: pending);
    expect(h, ImageStore.hashOf(rectified));
    expect(h, hasLength(64));
    expect(store.has(h), isTrue);
    expect(store.thumb(h).existsSync(), isTrue);
    expect(store.orphanedPending(), isEmpty);
    expect(await store.commit(originalJpeg: original, rectifiedJpeg: rectified, thumbJpeg: thumb), h);
  });
}
