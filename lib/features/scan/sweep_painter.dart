import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../scan/geometry.dart';
import '../../scan/sweep_tracker.dart';

/// Done cards: green, with a check and "Done" (owner's wording, S14c.2).
const sweepDoneColor = Color(0xFF2E9E5B);

/// Cards that could not be read: amber, "Hover again".
const sweepMissedColor = Color(0xFFE0A030);

/// Draws each card in Sweep mode over the camera preview:
/// found = accent outline; reading = accent wipe sweeping across the card;
/// done = green tint, check and the note ("Done"); missed = amber, "Hover again".
/// [cards] are in a preview frame of size [frame]; [wipe] runs 0..1 repeatedly.
class SweepPainter extends CustomPainter {
  final List<(Quad, SweepState, String?)> cards;
  final Size frame;
  final double wipe;

  /// Optional opacity per card (fading out once it leaves the view); 1 when omitted.
  final List<double>? opacities;
  SweepPainter(this.cards, this.frame, this.wipe, {this.opacities});

  @override
  void paint(Canvas canvas, Size size) {
    if (frame == Size.zero) return;
    final sx = size.width / frame.width, sy = size.height / frame.height;
    for (final (i, (q, state, note)) in cards.indexed) {
      final a = opacities == null || i >= opacities!.length ? 1.0 : opacities![i];
      if (a <= 0) continue;
      if (a < 1) canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, a));
      final pts = [for (final p in q.corners) Offset(p.x * sx, p.y * sy)];
      final path = Path()..addPolygon(pts, true);
      final bounds = path.getBounds();
      switch (state) {
        case SweepState.found:
          _outline(canvas, path, Tokens.brandOrange);
        case SweepState.reading:
          canvas.drawPath(path, Paint()..color = Tokens.brandOrange.withValues(alpha: 0.12));
          canvas.save();
          canvas.clipPath(path);
          // A band of accent colour sweeping along the card's long side.
          final across = bounds.width >= bounds.height;
          final span = across ? bounds.width : bounds.height;
          final band = span * 0.35;
          final pos = -band + wipe * (span + band);
          final rect = across
              ? Rect.fromLTWH(bounds.left + pos, bounds.top, band, bounds.height)
              : Rect.fromLTWH(bounds.left, bounds.top + pos, bounds.width, band);
          const accent = Tokens.brandOrange;
          canvas.drawRect(
            rect,
            Paint()
              ..shader = LinearGradient(
                begin: across ? Alignment.centerLeft : Alignment.topCenter,
                end: across ? Alignment.centerRight : Alignment.bottomCenter,
                colors: [accent.withValues(alpha: 0), accent.withValues(alpha: 0.55), accent.withValues(alpha: 0)],
              ).createShader(rect),
          );
          canvas.restore();
          _outline(canvas, path, accent);
        case SweepState.done:
          canvas.drawPath(path, Paint()..color = sweepDoneColor.withValues(alpha: 0.35));
          _outline(canvas, path, sweepDoneColor);
          _label(canvas, bounds, '✓ ${note ?? 'Done'}', sweepDoneColor);
        case SweepState.missed:
          canvas.drawPath(path, Paint()..color = sweepMissedColor.withValues(alpha: 0.22));
          _outline(canvas, path, sweepMissedColor);
          _label(canvas, bounds, 'Hover again', sweepMissedColor);
      }
      if (a < 1) canvas.restore();
    }
  }

  void _outline(Canvas canvas, Path path, Color color) => canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color,
  );

  void _label(Canvas canvas, Rect bounds, String text, Color bg) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: math.max(12, math.min(18, bounds.shortestSide * 0.18)),
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const pad = EdgeInsets.symmetric(horizontal: 10, vertical: 5);
    final box = Rect.fromCenter(
      center: bounds.center,
      width: tp.width + pad.horizontal,
      height: tp.height + pad.vertical,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(99)), Paint()..color = bg);
    tp.paint(canvas, Offset(box.left + pad.left, box.top + pad.top));
  }

  @override
  bool shouldRepaint(SweepPainter old) => true; // tracks change in place; the wipe animates
}
