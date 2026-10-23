// Cases from the screen recording of the third Sweep test on the S25 Ultra
// (0.7.2): ghost outlines, outlines over two cards, overlays drifting off their
// card, and a shared office number taken as the same person.
import 'dart:typed_data';
import 'dart:ui';

import 'package:card_organizer/core/cards/card_queue_repository.dart';
import 'package:card_organizer/features/scan/sweep_painter.dart';
import 'package:card_organizer/parser/ocr.dart';
import 'package:card_organizer/scan/card_detector.dart';
import 'package:card_organizer/scan/geometry.dart';
import 'package:card_organizer/scan/scan_pipeline.dart';
import 'package:card_organizer/scan/sweep_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

Quad box(double x, double y, double w, double h) => Quad([Pt(x, y), Pt(x + w, y), Pt(x + w, y + h), Pt(x, y + h)]);

ScannedSide side(String hash, List<String> lines) =>
    ScannedSide(hash: hash, thumb: Uint8List(0), issues: const [], ocr: OcrPage.fromText(lines));

void main() {
  group('ghost outlines are not cards', () {
    const w = 480.0, h = 640.0;
    test('a card at an angle passes', () {
      expect(sweepShapeOk(box(100, 100, 175, 100), width: w, height: h), isTrue);
      final tilted = Quad([const Pt(100, 120), const Pt(260, 90), const Pt(278, 190), const Pt(118, 220)]);
      expect(sweepShapeOk(tilted, width: w, height: h), isTrue);
    });

    test('a thin sliver along the table edge fails', () {
      expect(sweepShapeOk(box(0, 600, 470, 30), width: w, height: h), isFalse);
    });

    test('a tiny speck fails', () {
      expect(sweepShapeOk(box(10, 10, 20, 12), width: w, height: h), isFalse);
    });

    test('a wedge fails on its corner angles', () {
      final wedge = Quad([const Pt(50, 100), const Pt(300, 100), const Pt(320, 300), const Pt(200, 120)]);
      expect(sweepShapeOk(wedge, width: w, height: h), isFalse);
    });

    test('an outline filling most of the view fails', () {
      expect(sweepShapeOk(box(10, 10, 460, 600), width: w, height: h), isFalse);
    });

    test('the tracker never outlines them', () {
      final tr = SweepTracker();
      final now = DateTime(2026, 10, 23, 12);
      tr.update([box(0, 600, 470, 30), box(100, 100, 175, 100)], [50, 50], width: w, height: h, now: now);
      expect(tr.tracks.length, 1);
      expect(tr.tracks.single.quad.corners.first.x, 100);
    });
  });

  group('outlines over two cards or half a card', () {
    test('an outline around another card is dropped; the card inside stays', () {
      final card = box(100, 100, 175, 100);
      final aroundTwo = box(80, 80, 400, 230);
      final merged = mergeSweepQuads([aroundTwo, card], 480 * 640, width: 480, height: 640);
      expect(merged, [card]);
    });

    test('an outline that does not sit on real edges is dropped', () {
      final real = box(100, 100, 175, 100);
      final half = box(100, 300, 175, 100);
      final merged = mergeSweepQuads(
        [real, half],
        480 * 640,
        width: 480,
        height: 640,
        support: (q) => identical(q, real) ? 0.95 : 0.4,
      );
      expect(merged, [real]);
    });

    test('edge support counts the outline points on edge pixels', () {
      final q = box(10, 10, 100, 60);
      bool onLeftAndTop(int x, int y) => x == 10 || y == 10;
      final s = edgeSupport(q, onLeftAndTop);
      expect(s, closeTo(0.5, 0.05));
      expect(edgeSupport(q, (_, _) => true), 1);
      expect(edgeSupport(q, (_, _) => false), 0);
    });
  });

  group('a new sweep starts from zero', () {
    test('reset clears the counter and every track', () {
      final tr = SweepTracker();
      final now = DateTime(2026, 10, 23, 12);
      tr.update([box(100, 100, 175, 100)], [50], width: 480, height: 640, now: now);
      tr.markDone(tr.tracks.single.id);
      expect(tr.doneCount, 1);
      tr.reset();
      expect(tr.doneCount, 0);
      expect(tr.total, 0);
      expect(tr.tracks, isEmpty);
    });
  });

  group('overlays stay on their card', () {
    test('a card out of the latest frame holds still instead of gliding', () {
      final tr = SweepTracker();
      final t0 = DateTime(2026, 10, 23, 12);
      DateTime at(int ms) => t0.add(Duration(milliseconds: ms));
      tr.update([box(40, 60, 175, 100), box(260, 300, 175, 100)], [50, 50], width: 480, height: 640, now: at(0));
      tr.update([box(60, 60, 175, 100), box(280, 300, 175, 100)], [50, 50], width: 480, height: 640, now: at(100));
      // Only the first card is seen in the next frame.
      tr.update([box(80, 60, 175, 100)], [50], width: 480, height: 640, now: at(200));
      final gone = tr.tracks.firstWhere((t) => t.quad.corners.first.x == 280);
      expect(tr.displayQuad(gone, at(250)).corners.first.x, 280);
    });

    test('the painter maps frame pixels onto the preview widget', () {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      // A 480 x 640 frame shown in a 960 x 1280 preview: twice the size.
      final painter = SweepPainter([(box(100, 100, 175, 100), SweepState.found, null)], const Size(480, 640), 0);
      painter.paint(canvas, const Size(960, 1280));
      recorder.endRecording();
      // The painter scales x and y by the same factor for a same-aspect preview.
      expect(960 / 480, 1280 / 640);
    });
  });

  group('one office number shared by a company is not one person', () {
    test('different names with the same office number are different cards', () {
      final bridgette = side('a', ['Bridgette Kipling', 'HR Manager', 'Enpress LLC', 'T 440.510.0108']);
      final justin = side('b', ['Justin Fink', 'Sales Engineer', 'Enpress LLC', 'T 440.510.0108']);
      expect(CardQueueRepository.sameCard(bridgette, justin), isFalse);
    });

    test('the same mobile is the same person, whatever the name reads as', () {
      final a = side('a', ['Rosa Delgado', 'Store Manager', 'Greenfield Garden Center', 'C 440 555 0185']);
      final b = side('b', ['Hr Manage', 'Greenfield', 'Cell 440.555.0185']);
      expect(CardQueueRepository.sameCard(a, b), isTrue);
    });

    test('the same office number with a close name is the same person', () {
      final a = side('a', ['Bridgette Kipling', 'HR Manager', 'Enpress LLC', 'T 440.510.0108']);
      final b = side('b', ['Bridgette Kipl', 'Enpress', 'T 440.510.0108']);
      expect(CardQueueRepository.sameCard(a, b), isTrue);
    });

    test('the same email is the same person', () {
      final a = side('a', ['Justin Fink', 'Enpress LLC', 'jfink@enpress.com']);
      final b = side('b', ['Justn Fink', 'jfink@enpress.com']);
      expect(CardQueueRepository.sameCard(a, b), isTrue);
    });
  });
}
