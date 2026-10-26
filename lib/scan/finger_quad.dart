import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'geometry.dart';

/// Skin-coloured pixels, for finding a card that someone is holding (the
/// thumb covers an edge or a corner). The usual YCrCb range, narrowed to the
/// more saturated half so cream-coloured card stock (Cr ~ 134) does not count.
/// Wood tables fall in the range too, which is why a mask covering a big part
/// of the frame is ignored ([fingerMaxShare]).
const skinYMin = 60, skinYMax = 225;
const skinCrMin = 140, skinCrMax = 173;
const skinCbMin = 77, skinCbMax = 120;

/// A finger is at least this share of the frame (after cleaning)...
const fingerMinShare = 0.008;

/// ...and a mask bigger than this is a table or a wall, not a finger.
const fingerMaxShare = 0.40;

/// A finger is one big blob; the red print on a card (a stripe, a logo) is
/// scattered specks that must not hide the card's own edge.
const fingerBlobShare = 0.004;

bool isSkinYCrCb(int y, int cb, int cr) =>
    y >= skinYMin && y <= skinYMax && cr >= skinCrMin && cr <= skinCrMax && cb >= skinCbMin && cb <= skinCbMax;

/// 0/255 mask of skin-coloured pixels in a BGR image (same size).
cv.Mat skinMaskBgr(cv.Mat bgr) {
  final ycc = cv.cvtColor(bgr, cv.COLOR_BGR2YCrCb);
  try {
    // Channel order in YCrCb is Y, Cr, Cb.
    return cv.inRangebyScalar(
      ycc,
      cv.Scalar(skinYMin.toDouble(), skinCrMin.toDouble(), skinCbMin.toDouble(), 0),
      cv.Scalar(skinYMax.toDouble(), skinCrMax.toDouble(), skinCbMax.toDouble(), 255),
    );
  } finally {
    ycc.dispose();
  }
}

/// [mask] (0/255) with every connected piece smaller than [minArea] px removed.
cv.Mat _bigBlobs(cv.Mat mask, double minArea) {
  final labels = cv.Mat.empty(), stats = cv.Mat.empty(), centroids = cv.Mat.empty();
  try {
    final n = cv.connectedComponentsWithStats(
      mask,
      labels,
      stats,
      centroids,
      8,
      cv.MatType.CV_32SC1.value,
      cv.CCL_DEFAULT,
    );
    final out = cv.Mat.zeros(mask.rows, mask.cols, cv.MatType.CV_8UC1);
    for (var i = 1; i < n; i++) {
      if (stats.at<int>(i, cv.CC_STAT_AREA) < minArea) continue;
      final one = cv.inRangebyScalar(labels, cv.Scalar(i.toDouble(), 0, 0, 0), cv.Scalar(i.toDouble(), 0, 0, 0));
      cv.bitwiseOR(out, one, dst: out);
      one.dispose();
    }
    return out;
  } finally {
    labels.dispose();
    stats.dispose();
    centroids.dispose();
  }
}

/// A fitted straight edge: a point on it, a unit direction, and the stretch of
/// it (parameters [t0]..[t1] along the direction from the point) that edges
/// were seen on.
class _Line {
  final double px, py, dx, dy;
  final double t0, t1;
  final bool virtual; // a frame border standing in for a card side beyond the frame
  bool nearFinger = false;
  _Line(this.px, this.py, this.dx, this.dy, this.t0, this.t1, {this.virtual = false});

  double get extent => t1 - t0;

  /// Angle in [0, pi).
  double get angle {
    var a = math.atan2(dy, dx);
    if (a < 0) a += math.pi;
    if (a >= math.pi) a -= math.pi;
    return a;
  }

  double distanceTo(double x, double y) => ((x - px) * dy - (y - py) * dx).abs();

  Pt at(double t) => Pt(px + dx * t, py + dy * t);

  Pt? intersect(_Line o) {
    final det = dx * o.dy - dy * o.dx;
    if (det.abs() < 1e-6) return null;
    final t = ((o.px - px) * o.dy - (o.py - py) * o.dx) / det;
    return Pt(px + dx * t, py + dy * t);
  }
}

double _angleDiff(double a, double b) {
  var d = (a - b).abs();
  if (d > math.pi) d = 2 * math.pi - d;
  return math.min(d, math.pi - d);
}

/// Result of the finger-aware card search on one frame.
class FingerSearch {
  /// Card outlines completed from the visible edges, best first.
  final List<Quad> quads;

  final cv.Mat _guard; // finger pixels, grown a little
  final Uint8List _guardBytes;
  final int cols, rows;

  FingerSearch._(this.quads, this._guard, this._guardBytes, this.cols, this.rows);

  /// Share of [q]'s outline that runs through the finger. A standard outline
  /// that touches the finger is a fit to card plus thumb, not to the card.
  double contact(Quad q) {
    var hit = 0, total = 0;
    for (var i = 0; i < 4; i++) {
      final a = q.corners[i], b = q.corners[(i + 1) % 4];
      final n = math.max(8, (a.distanceTo(b) / 3).round());
      for (var k = 0; k <= n; k++) {
        final x = (a.x + (b.x - a.x) * k / n).round(), y = (a.y + (b.y - a.y) * k / n).round();
        total++;
        if (x >= 0 && y >= 0 && x < cols && y < rows && _guardBytes[y * cols + x] != 0) hit++;
      }
    }
    return total == 0 ? 0 : hit / total;
  }

  void dispose() => _guard.dispose();
}

/// Finds card outlines when a finger covers part of the edge. The finger's
/// pixels are masked out of the edge map, straight lines are fitted to what is
/// left, and an outline is made from them:
///  * four lines (a hidden corner is where its two lines meet);
///  * three lines plus the frame border (a card running off the frame);
///  * two parallel sides and one cross side, the fourth inferred at a business
///    card's width on the finger's side (a thumb over a whole edge).
/// Up to ~35% of the outline may be hidden behind the finger, but every visible
/// side must follow real edges.
///
/// [gray] is the (about 640 px) detection frame, [skin] a 0/255 mask the same
/// size. Null when there is no finger to speak of (the normal search applies).
FingerSearch? findFingerQuads(cv.Mat gray, cv.Mat skin) {
  final w = gray.cols, h = gray.rows;
  final area = (w * h).toDouble();
  final rawShare = cv.countNonZero(skin) / area;
  if (rawShare < fingerMinShare || rawShare > fingerMaxShare) return null;
  final k5 = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
  final k9 = cv.getStructuringElement(cv.MORPH_RECT, (9, 9));
  final k41 = cv.getStructuringElement(cv.MORPH_RECT, (41, 41));
  final speckled = cv.morphologyEx(skin, cv.MORPH_OPEN, k5);
  final opened = _bigBlobs(speckled, fingerBlobShare * area);
  speckled.dispose();
  final share = cv.countNonZero(opened) / area;
  if (share < fingerMinShare || share > fingerMaxShare) {
    for (final m in [k5, k9, k41, opened]) {
      m.dispose();
    }
    return null;
  }
  final guard = cv.dilate(opened, k9);
  final guardBytes = Uint8List.fromList(guard.data);
  final near = cv.dilate(guard, k41);
  final nearBytes = Uint8List.fromList(near.data);
  final clahe = cv.CLAHE.create(2.0, (8, 8));
  final eq = clahe.apply(gray);
  final blur = cv.gaussianBlur(eq, (5, 5), 0);
  final edges = cv.canny(blur, 30, 90);
  final notGuard = cv.bitwiseNOT(guard);
  final visible = cv.bitwiseAND(edges, notGuard);
  final slack = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
  final fat = cv.dilate(visible, slack);
  final fatBytes = Uint8List.fromList(fat.data);
  final maxDim = math.max(w, h).toDouble();
  final lines = cv.HoughLinesP(visible, 1, math.pi / 180, 24, minLineLength: 0.09 * maxDim, maxLineGap: 14);
  final segs = <List<double>>[];
  for (var i = 0; i < lines.rows; i++) {
    final v = lines.at<cv.Vec4i>(i, 0);
    segs.add([v.val1.toDouble(), v.val2.toDouble(), v.val3.toDouble(), v.val4.toDouble()]);
  }
  for (final m in [k5, k9, k41, opened, near, eq, blur, edges, notGuard, visible, slack, fat, lines]) {
    m.dispose();
  }
  clahe.dispose();

  final real = _mergeSegments(segs, maxDim);
  // A card held in a hand has an edge that comes within reach of the finger.
  for (final l in real) {
    for (var t = l.t0; t <= l.t1 && !l.nearFinger; t += 4) {
      final p = l.at(t), x = p.x.round(), y = p.y.round();
      if (x >= 0 && y >= 0 && x < w && y < h && nearBytes[y * w + x] != 0) l.nearFinger = true;
    }
  }
  final borders = <_Line>[
    _Line(w / 2, 0, 1, 0, -w / 2, w / 2, virtual: true),
    _Line(w / 2, h - 1.0, 1, 0, -w / 2, w / 2, virtual: true),
    _Line(0, h / 2, 0, 1, -h / 2, h / 2, virtual: true),
    _Line(w - 1.0, h / 2, 0, 1, -h / 2, h / 2, virtual: true),
  ];
  final scored = <(double, Quad)>[];

  // Tallies samples (counted), edge pixels (hits), finger pixels (masked) and
  // edgeless pixels next to the finger (gap: its shadow and blur) along a side.
  _Tally tally(Pt a, Pt b) {
    final n = math.max(8, (a.distanceTo(b) / 3).round());
    var hits = 0, masked = 0, counted = 0, gap = 0;
    for (var k = 1; k < n; k++) {
      final x = (a.x + (b.x - a.x) * k / n).round(), y = (a.y + (b.y - a.y) * k / n).round();
      if (x < 0 || y < 0 || x >= w || y >= h) continue;
      counted++;
      if (guardBytes[y * w + x] != 0) {
        masked++;
      } else if (fatBytes[y * w + x] != 0) {
        hits++;
      } else if (nearBytes[y * w + x] != 0) {
        gap++;
      }
    }
    return (counted, hits, masked, gap);
  }

  final all = [...real, ...borders];
  for (var i = 0; i < all.length; i++) {
    for (var j = i + 1; j < all.length; j++) {
      for (var k = j + 1; k < all.length; k++) {
        for (var l = k + 1; l < all.length; l++) {
          final four = [all[i], all[j], all[k], all[l]];
          final virtuals = four.where((e) => e.virtual).length;
          if (virtuals > 1 || four.length - virtuals < 3 || !four.any((e) => e.nearFinger)) continue;
          final best = _bestQuad(four, w, h, area, tally);
          if (best != null) scored.add(best);
        }
      }
    }
  }
  // Two parallel sides and a cross side: the fourth is inferred.
  for (var i = 0; i < real.length; i++) {
    for (var j = i + 1; j < real.length; j++) {
      if (_angleDiff(real[i].angle, real[j].angle) > _parallelMax) continue;
      for (var k = 0; k < real.length; k++) {
        if (k == i || k == j) continue;
        if (!(real[i].nearFinger || real[j].nearFinger || real[k].nearFinger)) continue;
        final best = _inferQuad(real[i], real[j], real[k], w, h, area, tally);
        if (best != null) scored.add(best);
      }
    }
  }
  scored.sort((a, b) => b.$1.compareTo(a.$1));
  final quads = <Quad>[];
  for (final (_, q) in scored) {
    if (quads.length == 3) break;
    if (quads.any((k) => _near(k, q))) continue;
    quads.add(q);
  }
  return FingerSearch._(quads, guard, guardBytes, w, h);
}

bool _near(Quad a, Quad b) {
  var s = 0.0;
  for (var i = 0; i < 4; i++) {
    s += a.corners[i].distanceTo(b.corners[i]);
  }
  return s / 4 < 0.05 * math.max(a.longSide, 1);
}

/// Groups Hough segments that lie on one straight edge and fits a line through
/// each group; the longest ones first.
List<_Line> _mergeSegments(List<List<double>> segs, double maxDim) {
  segs.sort((a, b) => _len(b).compareTo(_len(a)));
  final groups = <List<List<double>>>[];
  final fits = <_Line>[];
  for (final s in segs) {
    final ang = _segAngle(s);
    final mx = (s[0] + s[2]) / 2, my = (s[1] + s[3]) / 2;
    var placed = false;
    for (var g = 0; g < groups.length; g++) {
      final f = fits[g];
      if (_angleDiff(ang, f.angle) < 6 * math.pi / 180 && f.distanceTo(mx, my) < 7) {
        groups[g].add(s);
        fits[g] = _fit(groups[g]);
        placed = true;
        break;
      }
    }
    if (!placed) {
      groups.add([s]);
      fits.add(_fit([s]));
    }
  }
  final out = fits.where((f) => f.extent >= 0.11 * maxDim).toList()..sort((a, b) => b.extent.compareTo(a.extent));
  return out.take(28).toList();
}

double _len(List<double> s) => math.sqrt(math.pow(s[2] - s[0], 2) + math.pow(s[3] - s[1], 2)).toDouble();

double _segAngle(List<double> s) {
  var a = math.atan2(s[3] - s[1], s[2] - s[0]);
  if (a < 0) a += math.pi;
  if (a >= math.pi) a -= math.pi;
  return a;
}

/// Total-least-squares line through the segments' end points.
_Line _fit(List<List<double>> group) {
  final xs = <double>[], ys = <double>[];
  for (final s in group) {
    xs
      ..add(s[0])
      ..add(s[2]);
    ys
      ..add(s[1])
      ..add(s[3]);
  }
  final n = xs.length;
  final cx = xs.reduce((a, b) => a + b) / n, cy = ys.reduce((a, b) => a + b) / n;
  var sxx = 0.0, syy = 0.0, sxy = 0.0;
  for (var i = 0; i < n; i++) {
    sxx += (xs[i] - cx) * (xs[i] - cx);
    syy += (ys[i] - cy) * (ys[i] - cy);
    sxy += (xs[i] - cx) * (ys[i] - cy);
  }
  final theta = 0.5 * math.atan2(2 * sxy, sxx - syy);
  final dx = math.cos(theta), dy = math.sin(theta);
  var lo = double.infinity, hi = double.negativeInfinity;
  for (var i = 0; i < n; i++) {
    final t = (xs[i] - cx) * dx + (ys[i] - cy) * dy;
    lo = math.min(lo, t);
    hi = math.max(hi, t);
  }
  return _Line(cx, cy, dx, dy, lo, hi);
}

typedef _Tally = (int, int, int, int);

const _parallelMax = 30 * math.pi / 180, _crossMin = 45 * math.pi / 180;

/// The best card outline the four [lines] make, or null.
(double, Quad)? _bestQuad(List<_Line> lines, int w, int h, double frameArea, _Tally Function(Pt, Pt) tally) {
  (double, Quad)? best;
  for (final pairing in const [
    [0, 1, 2, 3],
    [0, 2, 1, 3],
    [0, 3, 1, 2],
  ]) {
    final a1 = lines[pairing[0]], a2 = lines[pairing[1]], b1 = lines[pairing[2]], b2 = lines[pairing[3]];
    if (_angleDiff(a1.angle, a2.angle) > _parallelMax || _angleDiff(b1.angle, b2.angle) > _parallelMax) continue;
    if ([
      for (final a in [a1, a2])
        for (final b in [b1, b2]) _angleDiff(a.angle, b.angle),
    ].any((d) => d < _crossMin)) {
      continue;
    }
    final c11 = a1.intersect(b1), c12 = a1.intersect(b2), c22 = a2.intersect(b2), c21 = a2.intersect(b1);
    if (c11 == null || c12 == null || c22 == null || c21 == null) continue;
    final q = _checked([c11, c12, c22, c21], w, h, frameArea);
    if (q == null) continue;
    // Each side: which line it lies on and its end points.
    final sides = [(a1, c11, c12), (a2, c21, c22), (b1, c11, c21), (b2, c12, c22)];
    var hits = 0, total = 0, masked = 0;
    var ok = true;
    for (final (line, p, r) in sides) {
      if (line.virtual) continue; // lies along the frame border: nothing to see
      final (n, hit, mask, gap) = tally(p, r);
      if (n <= 0) {
        ok = false;
        break;
      }
      hits += hit;
      masked += mask;
      total += n;
      // Seen or hidden by the finger: nothing else may be missing.
      if ((hit + mask + gap) / n < 0.85 || (hit / n < 0.4 && (mask + gap) / n < 0.1)) {
        ok = false;
        break;
      }
    }
    if (!ok || total == 0 || masked / total > 0.35 || hits / total < 0.5) continue;
    final score = hits / total + 0.15 * (q.area / frameArea);
    if (best == null || score > best.$1) best = (score, q);
  }
  return best;
}

/// A card whose whole fourth side is behind the finger: [a1] and [a2] are two
/// parallel sides, [b] the side across them. The fourth is [b] moved along the
/// sides by a card's length (or width), and has to lie in the finger.
(double, Quad)? _inferQuad(_Line a1, _Line a2, _Line b, int w, int h, double frameArea, _Tally Function(Pt, Pt) tally) {
  if (_angleDiff(a1.angle, b.angle) < _crossMin || _angleDiff(a2.angle, b.angle) < _crossMin) return null;
  final p1 = a1.intersect(b), p2 = a2.intersect(b);
  if (p1 == null || p2 == null) return null;
  // The sides' common direction, pointing the same way for both.
  final flip = a1.dx * a2.dx + a1.dy * a2.dy >= 0 ? 1.0 : -1.0;
  var ux = a1.dx + a2.dx * flip, uy = a1.dy + a2.dy * flip;
  final un = math.sqrt(ux * ux + uy * uy);
  if (un < 1e-6) return null;
  ux /= un;
  uy /= un;
  final across = p1.distanceTo(p2); // the card's size across the two sides
  if (across < 20) return null;
  (double, Quad)? best;
  for (final aspect in const [1.75, 1.545, 1.65]) {
    for (final len in [across * aspect, across / aspect]) {
      for (final sign in const [1.0, -1.0]) {
        final shift = len * sign;
        final b2 = _Line(b.px + ux * shift, b.py + uy * shift, b.dx, b.dy, b.t0, b.t1);
        final c12 = a1.intersect(b2), c22 = a2.intersect(b2);
        if (c12 == null || c22 == null) continue;
        final q = _checked([p1, c12, c22, p2], w, h, frameArea);
        if (q == null) continue;
        final (nA1, hA1, mA1, gA1) = tally(p1, c12);
        final (nA2, hA2, mA2, gA2) = tally(p2, c22);
        final (nB, hB, mB, gB) = tally(p1, p2);
        final (nH, hH, mH, gH) = tally(c12, c22); // the inferred side: has to be behind the finger
        final seen = nA1 + nA2 + nB;
        if (seen <= 0 || nH <= 0 || (mH + gH) / nH < 0.5) continue;
        // What shows of the inferred side must be a real edge: bare table there means the guess is off.
        if ((nH - hH - mH - gH) / nH > 0.55) continue;
        if ((hA1 + mA1 + gA1) / math.max(nA1, 1) < 0.65 || (hA2 + mA2 + gA2) / math.max(nA2, 1) < 0.65) continue;
        if ((hB + mB + gB) / math.max(nB, 1) < 0.85) continue;
        final hits = hA1 + hA2 + hB;
        if (hits / seen < 0.5 || (mA1 + mA2 + mB) / seen > 0.35) continue;
        final score =
            hits / seen +
            0.15 * (q.area / frameArea) -
            0.05 -
            (1.75 - aspect) *
                0.25; // a US business card unless the sides say otherwise // a little less sure than four seen sides
        if (best == null || score > best.$1) best = (score, q);
      }
    }
  }
  return best;
}

/// [corners] as a card-shaped, convex quad inside (or just outside) the frame.
Quad? _checked(List<Pt> corners, int w, int h, double frameArea) {
  if (corners.any((p) => p.x < -0.06 * w || p.y < -0.06 * h || p.x > 1.06 * w || p.y > 1.06 * h)) return null;
  final q = Quad(corners);
  if (!q.isConvex) return null;
  if (pickCardQuad([q], frameArea: frameArea, minAreaRatio: 0.02, maxAspectError: 0.22) == null) return null;
  return q;
}
