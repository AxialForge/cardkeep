import 'package:card_organizer/features/scan/sweep_painter.dart';
import 'package:card_organizer/scan/geometry.dart';
import 'package:card_organizer/scan/sweep_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Quad card(double x, double y) => Quad([Pt(x, y), Pt(x + 175, y), Pt(x + 175, y + 100), Pt(x, y + 100)]);

void main() {
  testWidgets('every sweep state paints without errors, at any wipe position', (tester) async {
    for (final wipe in [0.0, 0.5, 1.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 480,
              child: CustomPaint(
                painter: SweepPainter(
                  [
                    (card(10, 10), SweepState.found, null),
                    (card(10, 130), SweepState.reading, null),
                    (card(10, 250), SweepState.done, 'Done'),
                    (card(10, 370), SweepState.missed, null),
                    (
                      Quad([const Pt(200, 10), const Pt(300, 10), const Pt(300, 185), const Pt(200, 185)]),
                      SweepState.reading,
                      null,
                    ),
                  ],
                  const Size(360, 480),
                  wipe,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('nothing is drawn before the first frame size is known', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CustomPaint(painter: SweepPainter([(card(0, 0), SweepState.done, null)], Size.zero, 0))),
    );
    expect(tester.takeException(), isNull);
  });

  test('done is green and missed is amber', () {
    expect(sweepDoneColor, const Color(0xFF2E9E5B));
    expect(sweepMissedColor, const Color(0xFFE0A030));
  });
}
