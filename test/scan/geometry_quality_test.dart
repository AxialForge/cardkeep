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
          const FrameMetrics(cardFound: true, sizeRatio: 0.6, sharpness: 150, glare: 0.002, highlight: 240, shadow: 30),
        ),
        isEmpty,
      );
    });
    test('issues come out in hint priority order', () {
      final issues = assess(
        const FrameMetrics(
          cardFound: true,
          cardCutOff: true,
          sizeRatio: 0.2,
          sharpness: 20,
          glare: 0.4,
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
      const white = FrameMetrics(cardFound: true, sizeRatio: 0.6, highlight: 252, shadow: 40);
      const black = FrameMetrics(cardFound: true, sizeRatio: 0.6, highlight: 235, shadow: 12);
      const washed = FrameMetrics(cardFound: true, sizeRatio: 0.6, highlight: 255, shadow: 240);
      const dim = FrameMetrics(cardFound: true, sizeRatio: 0.6, highlight: 70, shadow: 5);
      expect(assess(white), isEmpty);
      expect(assess(black), isEmpty);
      expect(assess(washed), [QualityIssue.bright]);
      expect(assess(dim), [QualityIssue.dark]);
    });
    test('no card short-circuits', () {
      expect(assess(const FrameMetrics(cardFound: false)), [QualityIssue.noCard]);
    });
  });

  group('auto-capture', () {
    final t0 = DateTime(2026);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));
    const none = <QualityIssue>[];

    test('fires once after 400 ms of a clean, steady card', () {
      final a = AutoCapture();
      expect(a.update(issues: none, steady: true, now: at(0)), isFalse);
      expect(a.update(issues: none, steady: true, now: at(200)), isFalse);
      expect(a.update(issues: none, steady: true, now: at(450)), isTrue);
      expect(a.update(issues: none, steady: true, now: at(600)), isFalse);
      a.reset();
      expect(a.update(issues: none, steady: true, now: at(0)), isFalse);
    });

    test('one shaky or flickery frame does not restart the count; two do', () {
      final a = AutoCapture();
      a.update(issues: none, steady: true, now: at(0));
      a.update(issues: none, steady: false, now: at(100)); // one miss: grace
      expect(a.update(issues: none, steady: true, now: at(420)), isTrue);

      final b = AutoCapture();
      b.update(issues: none, steady: true, now: at(0));
      b.update(issues: const [QualityIssue.cutOff], steady: true, now: at(100));
      b.update(issues: none, steady: false, now: at(150)); // second miss: restart
      expect(b.update(issues: none, steady: true, now: at(420)), isFalse);
      expect(b.update(issues: none, steady: true, now: at(900)), isTrue);
    });

    test('soft issues delay the shot; hard ones block it', () {
      final a = AutoCapture();
      const glare = [QualityIssue.glare];
      expect(a.update(issues: glare, steady: true, now: at(0)), isFalse);
      expect(a.update(issues: glare, steady: true, now: at(600)), isFalse);
      expect(a.update(issues: glare, steady: true, now: at(950)), isTrue);

      final b = AutoCapture();
      const small = [QualityIssue.tooSmall];
      for (var ms = 0; ms <= 3000; ms += 100) {
        expect(b.update(issues: small, steady: true, now: at(ms)), isFalse);
      }
    });
  });

  test('size gate: a card spanning ~60% of the view width is close enough', () {
    // Portrait 720x1280 preview, card 430 px wide: was 'Move closer' under the
    // old 45%-of-area rule (430x245 / 720x1280 = 11%).
    expect(assess(const FrameMetrics(cardFound: true, sizeRatio: 430 / 720)), isEmpty);
    expect(assess(const FrameMetrics(cardFound: true, sizeRatio: 250 / 720)), [QualityIssue.tooSmall]);
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
