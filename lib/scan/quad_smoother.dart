import 'geometry.dart';

/// What the live outline shows for one analysed preview frame.
class SmoothedQuad {
  /// The outline to draw and to judge steadiness on.
  final Quad quad;

  /// 1 while the card is seen; fades towards [QuadSmoother.heldOpacity] while
  /// the last good outline is only being held after a missed detection.
  final double opacity;

  /// True when this frame had no detection and [quad] is the held outline.
  final bool held;

  /// True when the smoothed outline barely moved since the previous frame, so
  /// hand jitter doesn't restart the auto-capture timer.
  final bool steady;

  const SmoothedQuad(this.quad, {required this.opacity, required this.held, required this.steady});
}

/// Calms the live card outline (phone test 2026-10-25: "the detector jumps
/// around a lot and drops out"):
///  * each corner moves a fraction [alpha] of the way to the new detection;
///  * a missed detection keeps the last outline for [holdMs], fading;
///  * a detection that jumps far from the outline (another candidate, a
///    mis-fit) is only taken after it shows up in two frames in a row;
///  * steadiness is judged on the smoothed outline, not the raw one.
class QuadSmoother {
  QuadSmoother({
    this.alpha = 0.35,
    this.holdMs = 600,
    this.jumpFraction = 0.25,
    this.steadyFraction = 0.012,
    this.heldOpacity = 0.35,
  });

  final double alpha;
  final int holdMs;

  /// Mean corner distance, as a share of the outline's long side, above which a
  /// detection counts as a jump.
  final double jumpFraction;

  /// Mean corner movement per frame, as a share of the frame width, that still
  /// counts as steady.
  final double steadyFraction;
  final double heldOpacity;

  Quad? _shown;
  Quad? _candidate;
  DateTime? _lastSeen;

  /// The outline currently shown, if any.
  Quad? get shown => _shown;

  void reset() {
    _shown = null;
    _candidate = null;
    _lastSeen = null;
  }

  /// Feeds one analysed frame. [detected] is the detector's card (null when it
  /// found none); [frameWidth] scales the steadiness check. Returns what to
  /// show, or null when there is nothing (the hold has run out).
  SmoothedQuad? update(Quad? detected, {required DateTime now, required double frameWidth}) {
    final before = _shown;
    if (detected != null) {
      final cur = _shown;
      if (cur == null) {
        _shown = detected;
        _candidate = null;
      } else if (_distance(detected, cur) <= jumpFraction * cur.longSide) {
        _shown = _blend(cur, detected, alpha);
        _candidate = null;
      } else {
        // A jump: wait for a second frame that agrees before moving.
        final cand = _candidate;
        if (cand != null && _distance(detected, cand) <= jumpFraction * cand.longSide) {
          _shown = detected;
          _candidate = null;
        } else {
          _candidate = detected;
        }
      }
      // A pending jump leaves the old outline on screen: it is "held" as far as
      // the clock is concerned until the candidate is confirmed.
      if (!identical(_shown, before) || _candidate == null) _lastSeen = now;
    }
    final shown = _shown;
    if (shown == null) return null;
    final seen = _lastSeen;
    final missedMs = detected != null && _candidate == null
        ? 0
        : (seen == null ? 0 : now.difference(seen).inMilliseconds);
    if (missedMs > holdMs) {
      reset();
      return null;
    }
    final held = detected == null || _candidate != null;
    final opacity = held ? 1 - (1 - heldOpacity) * (missedMs / holdMs).clamp(0.0, 1.0) : 1.0;
    final moved = before == null ? double.infinity : _distance(shown, before);
    final steady = held || moved <= steadyFraction * frameWidth;
    return SmoothedQuad(shown, opacity: opacity, held: held, steady: steady);
  }

  /// Mean distance between matching corners.
  static double _distance(Quad a, Quad b) {
    var s = 0.0;
    for (var i = 0; i < 4; i++) {
      s += a.corners[i].distanceTo(b.corners[i]);
    }
    return s / 4;
  }

  static Quad _blend(Quad from, Quad to, double t) => Quad([
    for (var i = 0; i < 4; i++)
      Pt(
        from.corners[i].x + (to.corners[i].x - from.corners[i].x) * t,
        from.corners[i].y + (to.corners[i].y - from.corners[i].y) * t,
      ),
  ]);
}
