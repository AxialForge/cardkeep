import 'package:card_organizer/parser/ocr.dart';
import 'package:card_organizer/scan/geometry.dart';
import 'package:card_organizer/scan/scan_pipeline.dart';
import 'package:card_organizer/scan/sweep_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 1.75:1 card centred at (x, y) in a 480 x 640 frame.
Quad card(double x, double y, {double w = 140}) {
  final h = w / 1.75;
  return Quad([Pt(x - w / 2, y - h / 2), Pt(x + w / 2, y - h / 2), Pt(x + w / 2, y + h / 2), Pt(x - w / 2, y + h / 2)]);
}

/// The fourth sweep test's Horsburgh & Scott card as ML Kit reads it, with each
/// line's angle as the engine reports it for the given turn.
OcrPage hs(double angle) => OcrPage([
  OcrLine('HORSBURGH & SCOTT', width: 200, height: 20, confidence: 0.9, angle: angle),
  OcrLine('Delivering The Difference', width: 180, height: 12, confidence: 0.9, angle: angle),
  OcrLine('Mike Norton', width: 120, height: 14, confidence: 0.92, angle: angle),
  OcrLine('Applications Engineer', width: 160, height: 12, confidence: 0.9, angle: angle),
  OcrLine('mnorton@horsburgh-scott.com', width: 200, height: 12, confidence: 0.9, angle: angle),
  OcrLine('216.432.5858 office', width: 140, height: 12, confidence: 0.9, angle: angle),
]);

OcrPage maxpak(double angle) => OcrPage([
  OcrLine('MAXPAK', width: 120, height: 24, confidence: 0.88, angle: angle),
  OcrLine('IMPROVING AUTOMATION', width: 180, height: 12, confidence: 0.86, angle: angle),
  OcrLine('Dick Yisha', width: 100, height: 14, confidence: 0.9, angle: angle),
  OcrLine('President', width: 80, height: 12, confidence: 0.9, angle: angle),
  OcrLine('info@maxpakusa.com', width: 150, height: 12, confidence: 0.9, angle: angle),
]);

void main() {
  group('why a card waits (fourth sweep test: outlined cards never captured)', () {
    test('a steady, sharp card in view is captured; each blocker is named', () {
      final t = SweepTracker();
      final start = DateTime(2026, 10, 23, 12);
      // Moving view: the card is outlined but waits with "moving".
      for (var i = 0; i < 4; i++) {
        t.update(
          [card(200 + i * 40.0, 300)],
          [40],
          width: 480,
          height: 640,
          now: start.add(Duration(milliseconds: 120 * i)),
        );
      }
      final moving = start.add(const Duration(milliseconds: 360));
      expect(t.next(width: 480, height: 640, now: moving), isNull);
      expect(t.tracks.single.wait, 'moving');
      // Held still: settles, then is ready.
      var now = moving;
      for (var i = 1; i <= 6; i++) {
        now = moving.add(Duration(milliseconds: 120 * i));
        t.update([card(320, 300)], [40], width: 480, height: 640, now: now);
      }
      expect(t.next(width: 480, height: 640, now: now)?.id, t.tracks.single.id);
      expect(t.tracks.single.wait, isNull);
    });

    test('a photo already in flight names the wait instead of hiding it', () {
      final t = SweepTracker();
      final start = DateTime(2026, 10, 23, 12);
      late DateTime now;
      for (var i = 0; i < 5; i++) {
        now = start.add(Duration(milliseconds: 120 * i));
        t.update([card(240, 300)], [40], width: 480, height: 640, now: now);
      }
      expect(t.next(width: 480, height: 640, now: now, busy: true), isNull);
      expect(t.tracks.single.wait, 'waiting for photo');
    });

    test('ordinary handheld drift (about 10% of the frame a second) no longer blocks capture', () {
      final t = SweepTracker();
      final start = DateTime(2026, 10, 23, 12);
      late DateTime now;
      // 6 px per 120 ms on a 640 px frame: about 8% a second, which the old 8% gate refused.
      for (var i = 0; i < 8; i++) {
        now = start.add(Duration(milliseconds: 120 * i));
        t.update([card(240 + i * 6.0, 300)], [40], width: 480, height: 640, now: now);
      }
      expect(t.next(width: 480, height: 640, now: now), isNotNull);
    });

    test('a card cut by the frame edge says "edge"; a blank patch says "no print"', () {
      final t = SweepTracker();
      final now = DateTime(2026, 10, 23, 12);
      t.update([card(70, 300), card(300, 300)], [40, 1], width: 480, height: 640, now: now);
      t.next(width: 480, height: 640, now: now);
      final byX = {for (final s in t.tracks) centre(s.quad).x.round(): s.wait};
      expect(byX[70], 'edge');
      expect(byX[300], 'no print');
    });
  });

  group('upright vs upside down (fourth sweep test: H&S and Maxpak came out upside down)', () {
    test('ML Kit line angles pick the upright turn when the text reads equally well', () {
      // The captured card was upside down: ML Kit still read it, at about 180 degrees.
      expect(bestRotation({0: orientationScore(hs(179)), 180: orientationScore(hs(1))}), 180);
      expect(bestRotation({0: orientationScore(maxpak(-178)), 180: orientationScore(maxpak(2))}), 180);
    });

    test('an upright card stays as captured', () {
      expect(bestRotation({0: orientationScore(hs(0.5)), 180: orientationScore(hs(180))}), 0);
      expect(bestRotation({0: orientationScore(maxpak(-1)), 180: orientationScore(maxpak(181))}), 0);
    });

    test('without angles nothing changes', () {
      expect(uprightness(OcrPage.fromText(['Mike Norton'])), 0);
    });
  });
}
