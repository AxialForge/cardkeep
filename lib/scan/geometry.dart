import 'dart:math' as math;

/// A point in image pixels.
class Pt {
  final double x, y;
  const Pt(this.x, this.y);
  Pt operator -(Pt o) => Pt(x - o.x, y - o.y);
  double get length => math.sqrt(x * x + y * y);
  double distanceTo(Pt o) => (this - o).length;
  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

/// Known business-card shapes, long side / short side (deep dive §2.2).
enum CardFormat {
  us(1.75, 3.5, 2.0), // 3.5 x 2 in
  eu(1.545, 3.346, 2.165), // 85 x 55 mm
  japan(1.65, 3.583, 2.165); // 91 x 55 mm

  final double aspect;
  final double longIn, shortIn;
  const CardFormat(this.aspect, this.longIn, this.shortIn);
}

/// A detected card outline: four corners ordered top-left, top-right,
/// bottom-right, bottom-left (clockwise in screen coordinates).
class Quad {
  final List<Pt> corners;
  Quad._(this.corners);

  /// Orders any four points into TL, TR, BR, BL.
  factory Quad(List<Pt> pts) {
    if (pts.length != 4) throw ArgumentError('A quad needs 4 points, got ${pts.length}');
    final bySum = [...pts]..sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
    final tl = bySum.first, br = bySum.last;
    final rest = [bySum[1], bySum[2]]..sort((a, b) => (a.y - a.x).compareTo(b.y - b.x));
    return Quad._([tl, rest[0], br, rest[1]]);
  }

  Pt get tl => corners[0];
  Pt get tr => corners[1];
  Pt get br => corners[2];
  Pt get bl => corners[3];

  /// Shoelace area in px².
  double get area {
    var s = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = corners[i], b = corners[(i + 1) % 4];
      s += a.x * b.y - b.x * a.y;
    }
    return s.abs() / 2;
  }

  /// Mean of opposite edges, so mild perspective doesn't skew the estimate.
  double get width => (tl.distanceTo(tr) + bl.distanceTo(br)) / 2;
  double get height => (tl.distanceTo(bl) + tr.distanceTo(br)) / 2;
  double get longSide => math.max(width, height);
  double get shortSide => math.min(width, height);
  double get aspect => shortSide == 0 ? 0 : longSide / shortSide;
  bool get isPortrait => height > width;

  bool get isConvex {
    double? sign;
    for (var i = 0; i < 4; i++) {
      final a = corners[i], b = corners[(i + 1) % 4], c = corners[(i + 2) % 4];
      final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (cross == 0) return false;
      sign ??= cross.sign;
      if (cross.sign != sign) return false;
    }
    return true;
  }

  Quad scaled(double f) => Quad._([for (final p in corners) Pt(p.x * f, p.y * f)]);

  @override
  String toString() => 'Quad$corners';
}

/// How well a quad matches a card shape: best format and relative aspect error.
class AspectMatch {
  final CardFormat format;
  final double error; // |aspect - target| / target
  const AspectMatch(this.format, this.error);
}

AspectMatch bestAspect(double aspect) {
  AspectMatch? best;
  for (final f in CardFormat.values) {
    final e = (aspect - f.aspect).abs() / f.aspect;
    if (best == null || e < best.error) best = AspectMatch(f, e);
  }
  return best!;
}

/// Picks the most card-like quad from detector candidates, or null.
/// [maxAspectError] 0.18 is loose on purpose: perspective stretches the shape
/// before rectifying; the 5% skew gate applies after the warp.
Quad? pickCardQuad(
  List<Quad> candidates, {
  required double frameArea,
  double minAreaRatio = 0.08,
  double maxAspectError = 0.18,
}) {
  Quad? best;
  var bestScore = double.negativeInfinity;
  for (final q in candidates) {
    if (!q.isConvex) continue;
    final ratio = q.area / frameArea;
    if (ratio < minAreaRatio || ratio > 0.98) continue;
    final m = bestAspect(q.aspect);
    if (m.error > maxAspectError) continue;
    // Bigger and squarer-to-a-real-card wins.
    final score = ratio - m.error * 2;
    if (score > bestScore) {
      bestScore = score;
      best = q;
    }
  }
  return best;
}

/// Output size for rectifying [q]: the matched card aspect at a long edge of
/// at least [minLong] px (deep dive: >= 1400 px) and at most [maxLong].
({int width, int height}) rectifiedSize(Quad q, {int minLong = 1400, int maxLong = 2000}) {
  final f = bestAspect(q.aspect).format;
  final long = q.longSide.clamp(minLong.toDouble(), maxLong.toDouble());
  final short = long / f.aspect;
  return q.isPortrait ? (width: short.round(), height: long.round()) : (width: long.round(), height: short.round());
}

/// Whether two quads are the same card within [tolerance] px per corner
/// (used for the "steady for 400 ms" auto-capture check).
bool sameQuad(Quad a, Quad b, double tolerance) {
  for (var i = 0; i < 4; i++) {
    if (a.corners[i].distanceTo(b.corners[i]) > tolerance) return false;
  }
  return true;
}
