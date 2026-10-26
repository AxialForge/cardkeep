import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'finger_quad.dart';
import 'geometry.dart';
import 'quality.dart';
import 'sweep_tracker.dart' show sweepShapeOk;

/// Greyscale pixels, row-major, no row padding (camera Y plane or a decoded still).
class GrayFrame {
  final Uint8List bytes;
  final int width, height;

  /// 0/255 per pixel, same size: skin-coloured pixels (a finger holding the
  /// card). Null when the frame has no colour (older callers, tests).
  final Uint8List? skin;
  const GrayFrame(this.bytes, this.width, this.height, {this.skin});
}

/// What the detector found in one frame. Quads are in the frame's pixel space.
class Detection {
  final Quad? card; // best single card
  final List<Quad> cards; // every separate card (pile mode)
  final FrameMetrics metrics;

  /// True when a finger hid part of the outline and the hidden corner or edge
  /// was completed from the visible ones.
  final bool completed;
  const Detection(this.card, this.cards, this.metrics, {this.completed = false});

  List<QualityIssue> get issues => assess(metrics);
  bool get clean => card != null && issues.isEmpty;
}

/// One rectified card cut from a still.
class RectifiedCard {
  final Uint8List jpeg; // rectified, q85, no EXIF
  final Uint8List thumbJpeg; // 400 px long edge
  final Quad quad; // in the still's pixel space
  final FrameMetrics metrics;
  final bool manualCrop; // no outline found; whole photo or user corners used
  final bool turned; // a portrait pile cut-out turned to landscape; may be upside down
  const RectifiedCard(
    this.jpeg,
    this.thumbJpeg,
    this.quad,
    this.metrics, {
    this.manualCrop = false,
    this.turned = false,
  });

  List<QualityIssue> get issues => assess(metrics);
}

const _detectLong = 640; // detection runs on a downscaled copy (deep dive §2.2)

/// Finds card outlines. Pure function: safe to run in an isolate via compute().
Detection detect(GrayFrame f) {
  final gray = cv.Mat.fromVec(cv.VecUChar.fromList(f.bytes), rows: f.height, cols: f.width, type: cv.MatType.CV_8UC1);
  final skinBytes = f.skin;
  final skin = skinBytes == null
      ? null
      : cv.Mat.fromVec(cv.VecUChar.fromList(skinBytes), rows: f.height, cols: f.width, type: cv.MatType.CV_8UC1);
  try {
    return _detectMat(gray, skin: skin);
  } finally {
    gray.dispose();
    skin?.dispose();
  }
}

Detection _detectMat(cv.Mat gray, {cv.Mat? skin}) {
  final scale = _detectLong / math.max(gray.cols, gray.rows);
  final small = scale < 1
      ? cv.resize(gray, ((gray.cols * scale).round(), (gray.rows * scale).round()), interpolation: cv.INTER_AREA)
      : gray.clone();
  final skinSmall = skin == null
      ? null
      : (scale < 1 ? cv.resize(skin, (small.cols, small.rows), interpolation: cv.INTER_NEAREST) : skin.clone());
  final s = scale < 1 ? scale : 1.0;
  FingerSearch? finger;
  try {
    final quads = _findQuads(small);
    final frameArea = (small.cols * small.rows).toDouble();
    var best = pickCardQuad(quads, frameArea: frameArea, minAreaRatio: 0.02);
    var all = _separateCards(quads, frameArea);
    var completed = false;
    // A finger over the card's edge or corner: the normal outline is missing, or
    // runs through the finger (a fit to card plus thumb). Complete the card
    // from the edges that can be seen.
    if (skinSmall != null) {
      finger = findFingerQuads(small, skinSmall);
      final byFinger = finger == null
          ? null
          : pickCardQuad(finger.quads, frameArea: frameArea, minAreaRatio: 0.02, maxAspectError: 0.22);
      // The standard outline is replaced when it touches the finger, or fits the
      // card shape clearly worse than the finger-completed one (card plus hand).
      if (byFinger != null &&
          (best == null ||
              finger!.contact(best) > 0.04 ||
              bestAspect(best.aspect).error > bestAspect(byFinger.aspect).error + 0.08)) {
        best = byFinger;
        all = [byFinger];
        completed = true;
      }
    }
    if (best == null) {
      return const Detection(null, [], FrameMetrics(cardFound: false));
    }
    final metrics = _measure(small, best, frameArea);
    return Detection(best.scaled(1 / s), [for (final q in all) q.scaled(1 / s)], metrics, completed: completed);
  } finally {
    finger?.dispose();
    skinSmall?.dispose();
    small.dispose();
  }
}

/// Card outlines. A second, more sensitive pass (contrast stretched, lower
/// edge thresholds) runs when the first finds nothing: a small card, or a
/// white card on a light table (phone test F23).
List<Quad> _findQuads(cv.Mat small) {
  final frameArea = (small.cols * small.rows).toDouble();
  final first = _findQuadsPass(small, 40, 120);
  if (pickCardQuad(first, frameArea: frameArea, minAreaRatio: 0.02) != null) return first;
  // Bright rooms: a glossy card blows out part of its edge, which the plain
  // pass misses. Local contrast (CLAHE) brings the edge back before the
  // global equalisation is tried.
  final clahe = cv.CLAHE.create(2.0, (8, 8));
  final local = clahe.apply(small);
  clahe.dispose();
  try {
    final second = [...first, ..._findQuadsPass(local, 30, 90)];
    if (pickCardQuad(second, frameArea: frameArea, minAreaRatio: 0.02) != null) return second;
    final eq = cv.equalizeHist(small);
    try {
      return [...second, ..._findQuadsPass(eq, 15, 45)];
    } finally {
      eq.dispose();
    }
  } finally {
    local.dispose();
  }
}

List<Quad> _findQuadsPass(cv.Mat small, double lo, double hi, {double minArea = 0.015}) {
  final blur = cv.gaussianBlur(small, (5, 5), 0);
  final edges = cv.canny(blur, lo, hi);
  final kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
  final closed = cv.morphologyEx(edges, cv.MORPH_CLOSE, kernel, iterations: 2);
  final (contours, hierarchy) = cv.findContours(closed, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);
  final frameArea = small.cols * small.rows;
  final out = <Quad>[];
  for (final c in contours) {
    // Small on purpose: a distant card must still be found to get "Move closer".
    if (cv.contourArea(c) < frameArea * minArea) continue;
    final approx = cv.approxPolyDP(c, 0.02 * cv.arcLength(c, true), true);
    if (approx.length == 4) {
      out.add(Quad([for (final p in approx) Pt(p.x.toDouble(), p.y.toDouble())]));
    } else {
      // A printed band or box touching the card's edge joins the card's outline,
      // which then has more than four corners: its convex hull is the card
      // (third recorded sweep: the Millennium card was never outlined).
      final hull = cv.VecPoint.fromList(_hull([for (final p in c) p]));
      final h4 = cv.approxPolyDP(hull, 0.04 * cv.arcLength(hull, true), true);
      if (h4.length == 4) out.add(Quad([for (final p in h4) Pt(p.x.toDouble(), p.y.toDouble())]));
      h4.dispose();
      hull.dispose();
    }
    approx.dispose();
  }
  for (final m in [blur, edges, kernel, closed]) {
    m.dispose();
  }
  contours.dispose();
  hierarchy.dispose();
  return out;
}

/// Convex hull of contour points (monotone chain), in order.
List<cv.Point> _hull(List<cv.Point> pts) {
  final p = [...pts]..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  if (p.length < 3) return p;
  int cross(cv.Point o, cv.Point a, cv.Point b) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  final lower = <cv.Point>[], upper = <cv.Point>[];
  for (final q in p) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, q) <= 0) {
      lower.removeLast();
    }
    lower.add(q);
  }
  for (final q in p.reversed) {
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, q) <= 0) {
      upper.removeLast();
    }
    upper.add(q);
  }
  return [...lower..removeLast(), ...upper..removeLast()];
}

/// A dark printed band along a card's edge (the Millennium card) hides that
/// edge against a dark table, so the card is found as two quads: the light
/// part and the band. Adds the four-sided hull of each such touching pair; the
/// shape and edge checks downstream decide whether it is a card.
List<Quad> _withPrintedBands(List<Quad> quads) {
  final out = [...quads];
  for (var i = 0; i < quads.length; i++) {
    for (var j = i + 1; j < quads.length; j++) {
      final a = quads[i], b = quads[j];
      if (overlapRatio(a, b) <= 0.05 && !_boxesTouch(a, b)) continue;
      final pts = _hull([
        for (final p in [...a.corners, ...b.corners]) cv.Point(p.x.round(), p.y.round()),
      ]);
      final vec = cv.VecPoint.fromList(pts);
      final h4 = cv.approxPolyDP(vec, 0.04 * cv.arcLength(vec, true), true);
      if (h4.length == 4) out.add(Quad([for (final p in h4) Pt(p.x.toDouble(), p.y.toDouble())]));
      h4.dispose();
      vec.dispose();
    }
  }
  return out;
}

bool _boxesTouch(Quad a, Quad b, {double slack = 4}) {
  double minX(Quad q) => q.corners.map((p) => p.x).reduce(math.min);
  double maxX(Quad q) => q.corners.map((p) => p.x).reduce(math.max);
  double minY(Quad q) => q.corners.map((p) => p.y).reduce(math.min);
  double maxY(Quad q) => q.corners.map((p) => p.y).reduce(math.max);
  return minX(a) <= maxX(b) + slack &&
      minX(b) <= maxX(a) + slack &&
      minY(a) <= maxY(b) + slack &&
      minY(b) <= maxY(a) + slack;
}

/// Card-shaped quads that don't sit inside one another (a pile on a table).
List<Quad> _separateCards(List<Quad> quads, double frameArea) {
  final cards = <Quad>[];
  final sorted = [...quads]..sort((a, b) => b.area.compareTo(a.area));
  for (final q in sorted) {
    if (pickCardQuad([q], frameArea: frameArea, minAreaRatio: 0.02) == null) continue;
    final c = _centre(q);
    // One card often yields two outlines (card edge and shadow, or card and
    // its printed border) that overlap without containing each other's centre:
    // keep one (phone test F17).
    if (cards.any((k) => _contains(k, c) || _contains(q, _centre(k)) || overlapRatio(k, q) > 0.3)) continue;
    cards.add(q);
  }
  return cards.take(6).toList();
}

/// Overlap of two quads' bounding boxes, as a share of the smaller box.
double overlapRatio(Quad a, Quad b) {
  (double, double, double, double) box(Quad q) => (
    q.corners.map((p) => p.x).reduce(math.min),
    q.corners.map((p) => p.y).reduce(math.min),
    q.corners.map((p) => p.x).reduce(math.max),
    q.corners.map((p) => p.y).reduce(math.max),
  );
  final (al, at, ar, ab) = box(a);
  final (bl, bt, br, bb) = box(b);
  final w = math.min(ar, br) - math.max(al, bl), h = math.min(ab, bb) - math.max(at, bt);
  if (w <= 0 || h <= 0) return 0;
  final smaller = math.min((ar - al) * (ab - at), (br - bl) * (bb - bt));
  return smaller <= 0 ? 0 : w * h / smaller;
}

Pt _centre(Quad q) =>
    Pt(q.corners.map((p) => p.x).reduce((a, b) => a + b) / 4, q.corners.map((p) => p.y).reduce((a, b) => a + b) / 4);

bool _contains(Quad q, Pt p) {
  var inside = false;
  for (var i = 0, j = 3; i < 4; j = i++) {
    final a = q.corners[i], b = q.corners[j];
    if ((a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) inside = !inside;
  }
  return inside;
}

/// Gate measurements on the card region (deep dive §2.1 table).
FrameMetrics _measure(cv.Mat small, Quad q, double frameArea) {
  final edge = math.max(small.cols, small.rows) * 0.015;
  final cutOff = q.corners.any((p) => p.x < edge || p.y < edge || p.x > small.cols - edge || p.y > small.rows - edge);
  final card = _warp(small, q, longEdge: math.max(q.longSide.round(), 64));
  try {
    final (glare, specular) = _clippedShares(card);
    final (shadow, highlight) = _percentiles(card);
    return FrameMetrics(
      cardFound: true,
      cardCutOff: cutOff,
      sizeRatio: q.longSide / math.min(small.cols, small.rows),
      glare: glare,
      specular: specular,
      highlight: highlight,
      shadow: shadow,
    );
  } finally {
    card.dispose();
  }
}

cv.Mat _warp(cv.Mat src, Quad q, {int? longEdge, ({int width, int height})? size}) {
  final sz = size ?? _sizeFor(q, longEdge!);
  final from = cv.VecPoint2f.fromList([for (final p in q.corners) cv.Point2f(p.x, p.y)]);
  final to = cv.VecPoint2f.fromList([
    cv.Point2f(0, 0),
    cv.Point2f(sz.width - 1.0, 0),
    cv.Point2f(sz.width - 1.0, sz.height - 1.0),
    cv.Point2f(0, sz.height - 1.0),
  ]);
  final m = cv.getPerspectiveTransform2f(from, to);
  final out = cv.warpPerspective(src, m, (sz.width, sz.height), flags: cv.INTER_CUBIC);
  from.dispose();
  to.dispose();
  m.dispose();
  return out;
}

({int width, int height}) _sizeFor(Quad q, int longEdge) {
  final aspect = bestAspect(q.aspect).format.aspect;
  final short = (longEdge / aspect).round();
  return q.isPortrait ? (width: short, height: longEdge) : (width: longEdge, height: short);
}

/// Longest side of the stored original photo. A 12-50 MP capture kept full
/// size made a library of ~2.5 MB per contact (phone test F35); the card itself
/// is cut from this copy and still clears the 1400 px rectified gate.
const originalLongEdge = 2000;

/// Re-encodes a photo without EXIF (OpenCV applies the orientation on decode
/// and writes none), at most [originalLongEdge] px. Returns the clean JPEG and
/// the decoded colour image the cards are cut from.
({Uint8List jpeg, cv.Mat color}) _cleanOriginal(Uint8List jpeg) {
  var color = cv.imdecode(jpeg, cv.IMREAD_COLOR);
  if (color.isEmpty) throw const FormatException('Not an image');
  final scale = originalLongEdge / math.max(color.cols, color.rows);
  if (scale < 1) {
    final small = cv.resize(color, (
      (color.cols * scale).round(),
      (color.rows * scale).round(),
    ), interpolation: cv.INTER_AREA);
    color.dispose();
    color = small;
  }
  final (_, enc) = cv.imencode('.jpg', color, params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 85]));
  return (jpeg: enc, color: color);
}

/// Processes a still photo: cleans the original, finds every card (one, or a
/// pile when [allCards]), and rectifies each. With [corners] (manual crop) the
/// detector is skipped. When nothing is found the whole photo is used and the
/// card is flagged for a manual crop.
({Uint8List original, List<RectifiedCard> cards, int width, int height}) processStill(
  Uint8List jpeg, {
  bool allCards = false,
  Quad? corners,
  bool rectified = false,
  Quad? fallback,

  /// When set, [fallback] is an outline in a preview frame of this size (the
  /// live outline of a single scan) and is mapped into the photo here.
  ({int width, int height})? fallbackFrame,
  ({int dx, int dy, int width, int height})? source,
}) {
  final clean = _cleanOriginal(jpeg);
  final color = clean.color;
  final gray = cv.cvtColor(color, cv.COLOR_BGR2GRAY);
  cv.Mat? skin;
  try {
    final frameArea = (color.cols * color.rows).toDouble();
    List<Quad> quads;
    var manual = false;
    if (rectified) {
      // A Sweep crop is the card already warped flat: use all of it.
      quads = [
        Quad([
          const Pt(0, 0),
          Pt(color.cols - 1.0, 0),
          Pt(color.cols - 1.0, color.rows - 1.0),
          Pt(0, color.rows - 1.0),
        ]),
      ];
    } else if (corners != null) {
      // Corners are set on the stored original; one from before originals were
      // downscaled is bigger than this copy, so scale them to match.
      final big = cv.imdecode(jpeg, cv.IMREAD_REDUCED_GRAYSCALE_8);
      final fullLong = math.max(big.cols, big.rows) * 8;
      big.dispose();
      final f = math.max(color.cols, color.rows) / fullLong;
      quads = [f < 0.95 ? corners.scaled(f) : corners];
      manual = true;
    } else {
      // A finger on the card is masked out of the edge search (see finger_quad.dart).
      skin = skinMaskBgr(color);
      final d = _detectMat(gray, skin: skin);
      quads = allCards && d.cards.length > 1 ? d.cards : [if (d.card != null) d.card!];
      // A Sweep crop: the tracked outline stands in when the edge search finds
      // nothing, or only something much smaller than the card (a logo box). A
      // single scan's live outline does the same when a finger blocks an edge.
      final stand = fallback == null || fallbackFrame == null
          ? fallback
          : mapPreviewToStill(fallback, fallbackFrame.width, fallbackFrame.height, color.cols, color.rows);
      if (stand != null && (quads.isEmpty || quads.first.area < stand.area * 0.5)) quads = [stand];
      if (quads.isEmpty) {
        manual = true;
        quads = [
          Quad([
            const Pt(0, 0),
            Pt(color.cols - 1.0, 0),
            Pt(color.cols - 1.0, color.rows - 1.0),
            Pt(0, color.rows - 1.0),
          ]),
        ];
      }
    }
    final cards = <RectifiedCard>[];
    for (final q in quads) {
      final size = rectified
          ? (width: color.cols, height: color.rows)
          : manual && corners == null
          ? (width: color.cols, height: color.rows)
          : rectifiedSize(q, minLong: Gates.minRectifiedLong);
      var rect = _warp(color, q, size: size);
      // Pile cut-outs come out sideways when the cards lie across the photo;
      // business cards are landscape, so turn them (the pipeline tries the other
      // way up when the text reads badly).
      final turn = allCards && !manual && quads.length > 1 && rect.rows > rect.cols;
      if (turn) {
        final r = cv.rotate(rect, cv.ROTATE_90_CLOCKWISE);
        rect.dispose();
        rect = r;
      }
      final rectGray = cv.cvtColor(rect, cv.COLOR_BGR2GRAY);
      // A Sweep crop is part of a still: whether the card is cut off is judged
      // on the whole still, not on the crop's own border.
      final src = source;
      final metrics = _measureRectified(
        rectGray,
        src == null ? q : Quad([for (final p in q.corners) Pt(p.x + src.dx, p.y + src.dy)]),
        frameArea,
        src?.width ?? color.cols,
        src?.height ?? color.rows,
        manual: manual && corners == null,
      );
      final (_, rectJpg) = cv.imencode('.jpg', rect, params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 85]));
      final tScale = 400 / math.max(rect.cols, rect.rows);
      final thumb = cv.resize(rect, (
        (rect.cols * tScale).round(),
        (rect.rows * tScale).round(),
      ), interpolation: cv.INTER_AREA);
      final (_, thumbJpg) = cv.imencode('.jpg', thumb, params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 80]));
      cards.add(RectifiedCard(rectJpg, thumbJpg, q, metrics, manualCrop: manual, turned: turn));
      rect.dispose();
      rectGray.dispose();
      thumb.dispose();
    }
    return (original: clean.jpeg, cards: cards, width: color.cols, height: color.rows);
  } finally {
    skin?.dispose();
    gray.dispose();
    color.dispose();
  }
}

/// How good a photo of a card is for reading: higher is better. Used to pick
/// the best of a quick burst when the card is glossy (a reflection that covers
/// the text in one shot is often gone in the next): a card found, sharp, with
/// the least clipped white. Decodes at a quarter size, so it is cheap.
double stillScore(Uint8List jpeg) {
  final color = cv.imdecode(jpeg, cv.IMREAD_REDUCED_COLOR_4);
  if (color.isEmpty) return 0;
  final gray = cv.cvtColor(color, cv.COLOR_BGR2GRAY);
  final skin = skinMaskBgr(color);
  try {
    final d = _detectMat(gray, skin: skin);
    final q = d.card;
    if (q == null) return 0;
    final card = _warp(gray, q, longEdge: math.min(q.longSide.round(), 1000).clamp(64, 1000));
    try {
      final (glare, specular) = _clippedShares(card);
      final lap = cv.laplacian(card, cv.MatType.CV_64F);
      final (_, std) = cv.meanStdDev(lap);
      lap.dispose();
      final sharp = std.val1 * std.val1;
      return 100 + math.min(sharp, 400) / 4 - specular * 300 - glare * 500;
    } finally {
      card.dispose();
    }
  } finally {
    skin.dispose();
    gray.dispose();
    color.dispose();
  }
}

/// Index of the best photo of [jpegs] ([stillScore]); the first wins a tie.
int pickBestStill(List<Uint8List> jpegs) {
  var best = 0;
  var bestScore = double.negativeInfinity;
  for (var i = 0; i < jpegs.length; i++) {
    final sc = stillScore(jpegs[i]);
    if (sc > bestScore + 1e-9) {
      bestScore = sc;
      best = i;
    }
  }
  return best;
}

FrameMetrics _measureRectified(cv.Mat rectGray, Quad q, double frameArea, int w, int h, {required bool manual}) {
  final scale = 1000 / math.max(rectGray.cols, rectGray.rows);
  final norm = cv.resize(rectGray, (
    (rectGray.cols * scale).round(),
    (rectGray.rows * scale).round(),
  ), interpolation: cv.INTER_AREA);
  final lap = cv.laplacian(norm, cv.MatType.CV_64F);
  final (_, std) = cv.meanStdDev(lap);
  final (glare, specular) = _clippedShares(norm);
  final edge = math.max(w, h) * 0.01;
  final m = FrameMetrics(
    cardFound: !manual,
    cardCutOff: !manual && q.corners.any((p) => p.x < edge || p.y < edge || p.x > w - edge || p.y > h - edge),
    // A still is judged on resolution, not framing: big enough when the card
    // reaches the 1400 px gate without upscaling.
    sizeRatio: q.longSide / Gates.minRectifiedLong * Gates.minSizeRatio,
    sharpness: std.val1 * std.val1,
    glare: glare,
    specular: specular,
    highlight: _percentiles(norm).$2,
    shadow: _percentiles(norm).$1,
  );
  norm.dispose();
  lap.dispose();
  return m;
}

/// How much of a greyscale card is clipped white (luminance >= 253).
/// Returns (glare, specular): [specular] counts every clipped pixel; [glare]
/// only clipped areas of at least [Gates.glareSpotMin] of the card, so the
/// small reflections on a glossy card, which don't hide the text, don't count.
(double, double) _clippedShares(cv.Mat card) {
  final (_, bright) = cv.threshold(card, 252, 255, cv.THRESH_BINARY);
  try {
    final total = card.cols * card.rows;
    final clipped = cv.countNonZero(bright);
    final specular = clipped / total;
    if (clipped < total * Gates.glareSpotMin) return (0.0, specular);
    final labels = cv.Mat.empty(), stats = cv.Mat.empty(), centroids = cv.Mat.empty();
    try {
      final n = cv.connectedComponentsWithStats(
        bright,
        labels,
        stats,
        centroids,
        8,
        cv.MatType.CV_32SC1.value,
        cv.CCL_DEFAULT,
      );
      var big = 0;
      for (var i = 1; i < n; i++) {
        final area = stats.at<int>(i, cv.CC_STAT_AREA);
        if (area >= total * Gates.glareSpotMin) big += area;
      }
      return (big / total, specular);
    } finally {
      labels.dispose();
      stats.dispose();
      centroids.dispose();
    }
  } finally {
    bright.dispose();
  }
}

/// 1st and 99th percentile luminance of an 8-bit greyscale image.
(double, double) _percentiles(cv.Mat gray) {
  final hist = List<int>.filled(256, 0);
  final data = gray.isContinuous ? gray.data : gray.clone().data;
  for (final v in data) {
    hist[v]++;
  }
  final n = data.length, lo = n * 0.01, hi = n * 0.99;
  var acc = 0;
  double? p5;
  for (var i = 0; i < 256; i++) {
    acc += hist[i];
    if (p5 == null && acc >= lo) p5 = i.toDouble();
    if (acc >= hi) return (p5!, i.toDouble());
  }
  return (p5 ?? 0, 255);
}

/// Second OCR pass for low-confidence or dark cards (deep dive §2.3): CLAHE
/// contrast, inverted for light-on-dark cards. Never a hard binarisation.
Uint8List enhanceForOcr(Uint8List rectifiedJpeg, {required bool invert}) {
  final color = cv.imdecode(rectifiedJpeg, cv.IMREAD_COLOR);
  final gray = cv.cvtColor(color, cv.COLOR_BGR2GRAY);
  final clahe = cv.CLAHE.create(2.0, (8, 8));
  var out = clahe.apply(gray);
  if (invert) {
    final inv = cv.bitwiseNOT(out);
    out.dispose();
    out = inv;
  }
  final (_, jpg) = cv.imencode('.jpg', out, params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 92]));
  for (final m in [color, gray, out]) {
    m.dispose();
  }
  clahe.dispose();
  return jpg;
}

/// True when the card is mostly dark (light text on a dark card).
bool isDarkCard(Uint8List rectifiedJpeg) {
  final g = cv.imdecode(rectifiedJpeg, cv.IMREAD_GRAYSCALE);
  final dark = cv.mean(g).val1 < 100;
  g.dispose();
  return dark;
}

/// The same card turned by [degrees] (90, 180 or 270), with a new thumbnail.
/// True when the card image is taller than wide (read from a reduced decode).
bool isPortraitJpeg(Uint8List jpeg) {
  final m = cv.imdecode(jpeg, cv.IMREAD_REDUCED_GRAYSCALE_8);
  final portrait = m.rows > m.cols;
  m.dispose();
  return portrait;
}

RectifiedCard rotateCard(RectifiedCard c, int degrees) {
  final m = cv.imdecode(c.jpeg, cv.IMREAD_COLOR);
  final code = switch (degrees) {
    90 => cv.ROTATE_90_CLOCKWISE,
    270 => cv.ROTATE_90_COUNTERCLOCKWISE,
    _ => cv.ROTATE_180,
  };
  final r = cv.rotate(m, code);
  final out = _encodeCard(r, c.quad, c.metrics, manualCrop: c.manualCrop);
  m.dispose();
  r.dispose();
  return out;
}

/// No card outline was found: cut the photo to the text on it, with a margin,
/// so the card fills the image instead of the whole table. [textBoxes] are OCR
/// line boxes in the card image's pixels. Null when the text already fills it.
RectifiedCard? cropToText(RectifiedCard c, List<(double, double, double, double)> textBoxes) {
  if (textBoxes.isEmpty) return null;
  final m = cv.imdecode(c.jpeg, cv.IMREAD_COLOR);
  try {
    var l = double.infinity, t = double.infinity, r = 0.0, b = 0.0;
    var lineH = 0.0;
    for (final (x, y, w, h) in textBoxes) {
      l = math.min(l, x);
      t = math.min(t, y);
      r = math.max(r, x + w);
      b = math.max(b, y + h);
      lineH = math.max(lineH, h);
    }
    // A margin of a few text lines, and at least a card's shape.
    final pad = math.max(lineH * 2.5, (r - l) * 0.08);
    final x0 = (l - pad).clamp(0, m.cols - 1).toDouble(), y0 = (t - pad).clamp(0, m.rows - 1).toDouble();
    final x1 = (r + pad).clamp(0, m.cols.toDouble()).toDouble(), y1 = (b + pad).clamp(0, m.rows.toDouble()).toDouble();
    if ((x1 - x0) * (y1 - y0) > m.cols * m.rows * 0.7) return null; // already mostly card
    final roi = m.region(cv.Rect(x0.round(), y0.round(), (x1 - x0).round(), (y1 - y0).round()));
    final out = _encodeCard(roi, c.quad, c.metrics, manualCrop: true);
    roi.dispose();
    return out;
  } finally {
    m.dispose();
  }
}

RectifiedCard _encodeCard(cv.Mat rect, Quad quad, FrameMetrics metrics, {required bool manualCrop}) {
  final (_, jpg) = cv.imencode('.jpg', rect, params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 85]));
  final s = 400 / math.max(rect.cols, rect.rows);
  final thumb = cv.resize(rect, ((rect.cols * s).round(), (rect.rows * s).round()), interpolation: cv.INTER_AREA);
  final (_, thumbJpg) = cv.imencode('.jpg', thumb, params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 80]));
  thumb.dispose();
  return RectifiedCard(jpg, thumbJpg, quad, metrics, manualCrop: manualCrop);
}

/// Crops a JPEG to a fractional rectangle (0..1 of width/height), upscaled so
/// small text reads well. Used by "Read a region" on the review screen.
Uint8List cropJpeg(
  Uint8List jpeg, {
  required double left,
  required double top,
  required double right,
  required double bottom,
}) {
  final m = cv.imdecode(jpeg, cv.IMREAD_COLOR);
  int px(double f, int size) => (f.clamp(0.0, 1.0) * size).round();
  final x = px(left, m.cols), y = px(top, m.rows);
  final w = (px(right, m.cols) - x).clamp(1, m.cols - x), h = (px(bottom, m.rows) - y).clamp(1, m.rows - y);
  final roi = m.region(cv.Rect(x, y, w, h));
  final scale = (1200 / math.max(w, h)).clamp(1.0, 4.0);
  final big = cv.resize(roi, ((w * scale).round(), (h * scale).round()), interpolation: cv.INTER_CUBIC);
  final (_, out) = cv.imencode('.jpg', big, params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 92]));
  for (final x in [m, roi, big]) {
    x.dispose();
  }
  return out;
}

/// One analysed preview frame in Sweep mode (S14c): every separate card and
/// how sharp each looks (variance of Laplacian on its box, ~480 px frame).
class SweepFrame {
  final List<Quad> cards; // in the frame's pixel space
  final List<double> sharpness;
  final int width, height;

  /// Time the detector took for this frame, for the debug readout.
  final int ms;
  const SweepFrame(this.cards, this.sharpness, this.width, this.height, {this.ms = 0});
}

/// Sweep frames are analysed at this long side (~480 px): small enough for
/// 8+ frames a second on a phone, big enough for a card at arm's length.
const sweepDetectLong = 480;

/// Most cards tracked at once in Sweep mode.
const sweepMaxCards = 12;

/// Intersection over union of two quads' bounding boxes.
double iou(Quad a, Quad b) {
  (double, double, double, double) box(Quad q) => (
    q.corners.map((p) => p.x).reduce(math.min),
    q.corners.map((p) => p.y).reduce(math.min),
    q.corners.map((p) => p.x).reduce(math.max),
    q.corners.map((p) => p.y).reduce(math.max),
  );
  final (al, at, ar, ab) = box(a);
  final (bl, bt, br, bb) = box(b);
  final w = math.min(ar, br) - math.max(al, bl), h = math.min(ab, bb) - math.max(at, bt);
  if (w <= 0 || h <= 0) return 0;
  final inter = w * h;
  final union = (ar - al) * (ab - at) + (br - bl) * (bb - bt) - inter;
  return union <= 0 ? 0 : inter / union;
}

/// Sweep's card list: card-shaped, small cards allowed (a wide shot of a
/// table), overlapping outlines of one card merged (IoU, or one inside the
/// other), biggest first, at most [sweepMaxCards].
///
/// [width] and [height] are the frame's, for the shape gate ([sweepShapeOk]).
/// [support] scores how much of a quad's outline lies on real edges (0..1,
/// [edgeSupport]); quads under 0.7 are dropped and, between overlapping quads,
/// the better supported one wins (third sweep test: outlines over two cards
/// or half a card).
List<Quad> mergeSweepQuads(
  List<Quad> quads,
  double frameArea, {
  double? width,
  double? height,
  double Function(Quad)? support,
}) {
  final cards = <Quad>[];
  final w = width ?? math.sqrt(frameArea), h = height ?? math.sqrt(frameArea);
  final scores = <Quad, double>{};
  final shaped = [
    for (final q in quads)
      if (pickCardQuad([q], frameArea: frameArea, minAreaRatio: 0.004, maxAspectError: 0.25) != null &&
          sweepShapeOk(q, width: w, height: h) &&
          (support == null || (scores[q] = support(q)) >= 0.7))
        q,
  ];
  // An outline around another card is the table edge, a tray, two cards side
  // by side or the frame border, not a card: it would swallow the one inside.
  // A small box inside a card (a logo panel, a printed band) is not a second
  // card, so it never makes the card look like a tray: only card-sized quads
  // inside count (at least 15% of it; third recorded
  // sweep: the Millennium and Maxpak cards lost to their own printed boxes).
  List<Quad> inside(Quad q) => [
    for (final o in shaped)
      if (!identical(o, q) && o.area < q.area * 0.6 && _contains(q, _centre(o))) o,
  ];
  bool holdsCards(Quad q) {
    final ins = inside(q);
    return ins.any((o) => o.area >= q.area * 0.15);
  }

  final kept = [
    for (final q in shaped)
      if (!holdsCards(q)) q,
  ];
  // Printed boxes inside a kept card are dropped, so they're never drawn or tracked.
  bool printedBox(Quad q) => kept.any((k) => !identical(k, q) && q.area < k.area * 0.15 && _contains(k, _centre(q)));
  double score(Quad q) => scores[q] ?? 1;
  final sorted =
      [
        for (final q in kept)
          if (!printedBox(q)) q,
      ]..sort((a, b) {
        final s = score(b).compareTo(score(a));
        return s != 0 && (score(a) - score(b)).abs() > 0.05 ? s : b.area.compareTo(a.area);
      });
  for (final q in sorted) {
    final c = _centre(q);
    // Quads of very different size only clash when one sits inside the other:
    // a small neighbour whose box overlaps a tilted card's box is still its own
    // card, and a printed box inside a card gives way to the card.
    bool clash(Quad k) {
      if (k.area < q.area * 0.15) return _contains(q, _centre(k));
      if (q.area < k.area * 0.15) return _contains(k, c);
      return iou(k, q) > 0.3 || _contains(k, c) || _contains(q, _centre(k)) || overlapRatio(k, q) > 0.5;
    }

    final hits = cards.where(clash).toList();
    if (hits.isNotEmpty && !hits.every((k) => k.area < q.area * 0.15)) continue;
    cards.removeWhere(hits.contains);
    cards.add(q);
    if (cards.length == sweepMaxCards) break;
  }
  return cards;
}

/// Share of [q]'s outline (sampled every few pixels along all four sides) that
/// lies on an edge pixel ([isEdge]). A real card's outline follows its border;
/// a quad joining two cards or cutting across one doesn't.
double edgeSupport(Quad q, bool Function(int x, int y) isEdge) {
  var hits = 0, total = 0;
  for (var i = 0; i < 4; i++) {
    final a = q.corners[i], b = q.corners[(i + 1) % 4];
    final n = math.max(8, (a.distanceTo(b) / 3).round());
    // Skip the corners themselves: rounded card corners don't follow the line.
    for (var k = 1; k < n; k++) {
      final t = k / n;
      total++;
      if (isEdge((a.x + (b.x - a.x) * t).round(), (a.y + (b.y - a.y) * t).round())) hits++;
    }
  }
  return total == 0 ? 0 : hits / total;
}

/// Finds all cards in a preview frame and measures each one's sharpness.
/// One pass on a contrast-normalised copy (cheaper than the single-card
/// detector's two passes, and finds dim or low-contrast cards).
SweepFrame sweepDetect(GrayFrame f) {
  final watch = Stopwatch()..start();
  final gray = cv.Mat.fromVec(cv.VecUChar.fromList(f.bytes), rows: f.height, cols: f.width, type: cv.MatType.CV_8UC1);
  final scale = sweepDetectLong / math.max(gray.cols, gray.rows);
  final small = scale < 1
      ? cv.resize(gray, ((gray.cols * scale).round(), (gray.rows * scale).round()), interpolation: cv.INTER_AREA)
      : gray.clone();
  final s = scale < 1 ? scale : 1.0;
  final eq = cv.equalizeHist(small);
  try {
    final frameArea = (small.cols * small.rows).toDouble();
    // Edges with two pixels of slack (approximated corners sit a little off the
    // border), for checking each outline sits on real edges.
    final blur = cv.gaussianBlur(eq, (5, 5), 0);
    final canny = cv.canny(blur, 30, 90);
    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
    final fat = cv.dilate(canny, kernel);
    final edgeBytes = fat.data;
    final cols = fat.cols, rows = fat.rows;
    final found = _withPrintedBands(_findQuadsPass(eq, 30, 90, minArea: 0.004));
    final cards = mergeSweepQuads(
      found,
      frameArea,
      width: cols.toDouble(),
      height: rows.toDouble(),
      support: (q) =>
          edgeSupport(q, (x, y) => x >= 0 && y >= 0 && x < cols && y < rows && edgeBytes[y * cols + x] != 0),
    );
    for (final m in [blur, canny, kernel, fat]) {
      m.dispose();
    }
    final sharp = <double>[];
    for (final q in cards) {
      final xs = q.corners.map((p) => p.x), ys = q.corners.map((p) => p.y);
      final x0 = xs.reduce(math.min).floor().clamp(0, small.cols - 1);
      final y0 = ys.reduce(math.min).floor().clamp(0, small.rows - 1);
      final x1 = xs.reduce(math.max).ceil().clamp(x0 + 1, small.cols);
      final y1 = ys.reduce(math.max).ceil().clamp(y0 + 1, small.rows);
      final roi = small.region(cv.Rect(x0, y0, x1 - x0, y1 - y0));
      final lap = cv.laplacian(roi, cv.MatType.CV_64F);
      final (_, std) = cv.meanStdDev(lap);
      sharp.add(std.val1 * std.val1);
      lap.dispose();
      roi.dispose();
    }
    return SweepFrame(
      [for (final q in cards) q.scaled(1 / s)],
      sharp,
      f.width,
      f.height,
      ms: watch.elapsedMilliseconds,
    );
  } finally {
    eq.dispose();
    small.dispose();
    gray.dispose();
  }
}

/// A preview frame's YUV 4:2:0 planes, copied out of the camera buffer (which
/// is reused once the stream callback returns). Landscape, as the sensor gives it.
class YuvFrame {
  final Uint8List y, u, v;
  final int width, height, yRowStride, uvRowStride, uvPixelStride;

  /// 90 or 270: how the frame is turned to portrait (as in the live detector).
  final int sensorOrientation;
  const YuvFrame(
    this.y,
    this.u,
    this.v, {
    required this.width,
    required this.height,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.sensorOrientation,
  });
}

/// [q] grown by [f] (0.03 = 3%) about its centre: a hair of margin so the
/// card's own edge is never cut, without reaching a neighbouring card.
Quad growQuad(Quad q, double f) {
  final cx = q.corners.map((p) => p.x).reduce((a, b) => a + b) / 4;
  final cy = q.corners.map((p) => p.y).reduce((a, b) => a + b) / 4;
  return Quad([for (final p in q.corners) Pt(cx + (p.x - cx) * (1 + f), cy + (p.y - cy) * (1 + f))]);
}

/// Sweep crops are warped straight from the tracked outline with this margin
/// (second sweep test: an 18% box margin took in the next card's text).
const sweepCropMargin = 0.03;

/// Perspective-warps [q] (with [sweepCropMargin]) out of [m] at about its own
/// resolution and encodes it. The result is the card itself, already
/// rectified: the pipeline reads it as is ([processStill] `rectified`).
Uint8List _warpSweepCrop(cv.Mat m, Quad q) {
  final g = growQuad(q, sweepCropMargin);
  final clamped = Quad([
    for (final p in g.corners) Pt(p.x.clamp(0, m.cols - 1.0).toDouble(), p.y.clamp(0, m.rows - 1.0).toDouble()),
  ]);
  final long = math.max(clamped.longSide.round(), 32);
  final out = _warp(m, clamped, longEdge: long);
  try {
    final (_, jpg) = cv.imencode('.jpg', out, params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 92]));
    return jpg;
  } finally {
    out.dispose();
  }
}

/// Cuts one card out of the preview frame itself (no still, so the preview
/// never stalls), turned to portrait, converted to colour and warped flat
/// along the tracked outline. [quad] is in the portrait detection frame
/// [frameWidth] x [frameHeight].
Uint8List cropYuvForSweep((YuvFrame f, Quad quad, int frameWidth, int frameHeight) a) {
  final (f, quad, fw, fh) = a;
  final pw = f.height, ph = f.width; // portrait size at full preview resolution
  final sx = pw / fw, sy = ph / fh;
  final q = Quad([for (final p in quad.corners) Pt(p.x * sx, p.y * sy)]);
  final box = growQuad(q, sweepCropMargin * 2);
  final xs = box.corners.map((p) => p.x), ys = box.corners.map((p) => p.y);
  final x0 = xs.reduce(math.min).floor().clamp(0, pw - 1), y0 = ys.reduce(math.min).floor().clamp(0, ph - 1);
  final x1 = xs.reduce(math.max).ceil().clamp(x0 + 1, pw), y1 = ys.reduce(math.max).ceil().clamp(y0 + 1, ph);
  final ow = x1 - x0, oh = y1 - y0;
  final bgr = Uint8List(ow * oh * 3);
  final cw = f.sensorOrientation == 270;
  var i = 0;
  for (var py = y0; py < y1; py++) {
    for (var px = x0; px < x1; px++) {
      // Portrait (px, py) -> sensor (ix, iy), the same turn as the live detector.
      final ix = cw ? f.width - 1 - py : py;
      final iy = cw ? px : f.height - 1 - px;
      final yy = f.y[iy * f.yRowStride + ix];
      final uvi = (iy >> 1) * f.uvRowStride + (ix >> 1) * f.uvPixelStride;
      final u = f.u[uvi] - 128, v = f.v[uvi] - 128;
      bgr[i++] = (yy + 1.772 * u).round().clamp(0, 255);
      bgr[i++] = (yy - 0.344 * u - 0.714 * v).round().clamp(0, 255);
      bgr[i++] = (yy + 1.402 * v).round().clamp(0, 255);
    }
  }
  final m = cv.Mat.fromList(oh, ow, cv.MatType.CV_8UC3, bgr);
  try {
    return _warpSweepCrop(m, Quad([for (final p in q.corners) Pt(p.x - x0, p.y - y0)]));
  } finally {
    m.dispose();
  }
}

/// Cuts one card out of a full-resolution still for Sweep mode, warped flat
/// along the tracked outline. [quad] is the card in a preview frame of
/// [frameWidth] x [frameHeight] (portrait, same field of view as the still).
Uint8List cropForSweep((Uint8List jpeg, Quad quad, int frameWidth, int frameHeight) a) {
  final (jpeg, quad, fw, fh) = a;
  var m = cv.imdecode(jpeg, cv.IMREAD_COLOR); // applies EXIF orientation
  if (m.isEmpty) throw const FormatException('Not an image');
  if ((m.cols > m.rows) != (fw > fh)) {
    final r = cv.rotate(m, cv.ROTATE_90_CLOCKWISE);
    m.dispose();
    m = r;
  }
  try {
    final sx = m.cols / fw, sy = m.rows / fh;
    return _warpSweepCrop(m, Quad([for (final p in quad.corners) Pt(p.x * sx, p.y * sy)]));
  } finally {
    m.dispose();
  }
}

/// One card cut out of a full-resolution still for Sweep (third sweep test):
/// a loose box around it, so the pipeline finds the card's own edges at full
/// resolution, with other card-sized tracked cards painted over in the table
/// colour (never over this card itself).
class SweepStillCrop {
  final Uint8List jpeg;

  /// The tracked outline inside [jpeg], used when the edge search finds nothing.
  final Quad fallback;

  /// Where the crop sits in the still, so "cut off" is judged on the still.
  final ({int dx, int dy, int width, int height}) source;

  /// Variance of Laplacian over the card in the still (blur check).
  final double sharpness;

  /// Share of the card's own area that is flat table colour (fourth sweep test:
  /// a half-black "triangle" card). Above [sweepMaxFlat] with no print the crop
  /// is not queued.
  final double flat;

  /// False when the cut is mostly flat (nothing to read): retry later.
  final bool ok;
  const SweepStillCrop(this.jpeg, this.fallback, this.source, this.sharpness, {this.flat = 0, this.ok = true});
}

/// Largest share of a card's area that may be flat table colour.
const sweepMaxFlat = 0.45;

/// A neighbour is painted out only when it is card-sized next to the target.
const sweepMaskMinRatio = 0.35;

/// ...and only when it covers less than this share of the target.
const sweepMaskMaxOverlap = 0.15;

/// Margin around a tracked card for its still crop: room for the edge search.
const sweepStillMargin = 0.10;

/// Maps a quad from the portrait preview frame [fw] x [fh] into a still of
/// [w] x [h] (same orientation). The preview shows the middle of the still
/// when their shapes differ, so the smaller scale applies, centred.
Quad mapPreviewToStill(Quad q, int fw, int fh, int w, int h) {
  final s = math.min(w / fw, h / fh);
  final ox = (w - fw * s) / 2, oy = (h - fh * s) / 2;
  return Quad([for (final p in q.corners) Pt(p.x * s + ox, p.y * s + oy)]);
}

/// Which of [others] (same coordinates as [target]) may be painted out of the
/// target's crop: card-sized ones that barely touch the target. Small ghost
/// outlines and printed boxes are never painted, whatever they overlap.
List<Quad> sweepMaskable(Quad target, List<Quad> others, {required int width, required int height}) {
  final tArea = math.max(target.area, 1.0);
  final tMask = cv.Mat.zeros(height, width, cv.MatType.CV_8UC1);
  _fill(tMask, target, cv.Scalar.all(255));
  final out = <Quad>[];
  for (final o in others) {
    if (o.area < tArea * sweepMaskMinRatio) continue;
    final oMask = cv.Mat.zeros(height, width, cv.MatType.CV_8UC1);
    _fill(oMask, o, cv.Scalar.all(255));
    final both = cv.bitwiseAND(tMask, oMask);
    final overlap = cv.countNonZero(both) / tArea;
    oMask.dispose();
    both.dispose();
    if (overlap < sweepMaskMaxOverlap) out.add(o);
  }
  tMask.dispose();
  return out;
}

void _fill(cv.Mat m, Quad q, cv.Scalar c, {double grow = 0, int dx = 0, int dy = 0}) {
  final g = grow == 0 ? q : growQuad(q, grow);
  final pts = cv.VecVecPoint.fromList([
    [for (final p in g.corners) cv.Point((p.x - dx).round(), (p.y - dy).round())],
  ]);
  cv.fillPoly(m, pts, c);
  pts.dispose();
}

/// Cuts [quad] out of a still with [sweepStillMargin], painting card-sized
/// [others] (other tracked cards, preview coords) in the crop's border colour so
/// a neighbour's text can't be read into this card. The card's own outline is
/// always put back last. If the cut is mostly flat colour anyway, it is redone
/// without painting anything.
SweepStillCrop cropStillForSweep((Uint8List jpeg, Quad quad, List<Quad> others, int frameWidth, int frameHeight) a) {
  final (jpeg, quad, others, fw, fh) = a;
  var m = cv.imdecode(jpeg, cv.IMREAD_COLOR); // applies EXIF orientation
  if (m.isEmpty) throw const FormatException('Not an image');
  if ((m.cols > m.rows) != (fw > fh)) {
    final r = cv.rotate(m, cv.ROTATE_90_CLOCKWISE);
    m.dispose();
    m = r;
  }
  try {
    final q = mapPreviewToStill(quad, fw, fh, m.cols, m.rows);
    final box = growQuad(q, sweepStillMargin);
    final xs = box.corners.map((p) => p.x), ys = box.corners.map((p) => p.y);
    final x0 = xs.reduce(math.min).floor().clamp(0, m.cols - 2), y0 = ys.reduce(math.min).floor().clamp(0, m.rows - 2);
    final x1 = xs.reduce(math.max).ceil().clamp(x0 + 2, m.cols), y1 = ys.reduce(math.max).ceil().clamp(y0 + 2, m.rows);
    final roi = m.region(cv.Rect(x0, y0, x1 - x0, y1 - y0));
    final orig = roi.clone();
    roi.dispose();
    final local = Quad([for (final p in q.corners) Pt(p.x - x0, p.y - y0)]);
    // Table colour: the mean of the crop's outer strip.
    final strip = math.max(2, (math.min(orig.cols, orig.rows) * 0.03).round());
    final top = orig.region(cv.Rect(0, 0, orig.cols, strip));
    final bottom = orig.region(cv.Rect(0, orig.rows - strip, orig.cols, strip));
    final mt = cv.mean(top), mb = cv.mean(bottom);
    top.dispose();
    bottom.dispose();
    final fill = cv.Scalar((mt.val1 + mb.val1) / 2, (mt.val2 + mb.val2) / 2, (mt.val3 + mb.val3) / 2, 0);
    // The card's own pixels, in crop coordinates.
    final self = cv.Mat.zeros(orig.rows, orig.cols, cv.MatType.CV_8UC1);
    _fill(self, local, cv.Scalar.all(255));
    final area = math.max(cv.countNonZero(self), 1);
    double flatShare(cv.Mat img) {
      final lo = cv.Mat.zeros(1, 1, cv.MatType.CV_8UC3), hi = cv.Mat.zeros(1, 1, cv.MatType.CV_8UC3);
      lo.setTo(cv.Scalar(fill.val1 - 4, fill.val2 - 4, fill.val3 - 4, 0));
      hi.setTo(cv.Scalar(fill.val1 + 4, fill.val2 + 4, fill.val3 + 4, 0));
      final flat = cv.inRange(img, lo, hi);
      final inside = cv.bitwiseAND(flat, self);
      final share = cv.countNonZero(inside) / area;
      for (final x in [lo, hi, flat, inside]) {
        x.dispose();
      }
      return share;
    }

    final maskable = sweepMaskable(quad, others, width: fw, height: fh);
    var crop = orig.clone();
    for (final o in maskable) {
      final mo = mapPreviewToStill(o, fw, fh, m.cols, m.rows);
      _fill(crop, mo, fill, grow: 0.04, dx: x0, dy: y0);
    }
    // The card itself is never painted over.
    orig.copyTo(crop, mask: self);
    final plain = flatShare(orig);
    var flat = flatShare(crop);
    if (maskable.isNotEmpty && flat > sweepMaxFlat && flat - plain > 0.15) {
      crop.dispose();
      crop = orig.clone(); // painting damaged the card: use the plain cut
      flat = plain;
    }
    final gray = cv.cvtColor(crop, cv.COLOR_BGR2GRAY);
    final scale = 1000 / math.max(gray.cols, gray.rows);
    final small = cv.resize(gray, (
      (gray.cols * scale).round(),
      (gray.rows * scale).round(),
    ), interpolation: cv.INTER_AREA);
    final lap = cv.laplacian(small, cv.MatType.CV_64F);
    final (_, std) = cv.meanStdDev(lap);
    gray.dispose();
    small.dispose();
    lap.dispose();
    final (_, enc) = cv.imencode('.jpg', crop, params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 92]));
    final sharp = std.val1 * std.val1;
    crop.dispose();
    orig.dispose();
    self.dispose();
    return SweepStillCrop(
      enc,
      local,
      (dx: x0, dy: y0, width: m.cols, height: m.rows),
      sharp,
      flat: flat,
      ok: !(flat > sweepMaxFlat && sharp < 15),
    );
  } finally {
    m.dispose();
  }
}

/// 64-bit difference hash of a card image (9x8 grey, each pixel brighter than
/// its right-hand neighbour). Two crops of one card differ by a few bits.
int dHash(Uint8List jpeg) {
  final g = cv.imdecode(jpeg, cv.IMREAD_REDUCED_GRAYSCALE_4);
  if (g.isEmpty) return 0;
  // Landscape first, so a card cut a quarter-turn apart hashes the same way.
  final upright = g.rows > g.cols ? cv.rotate(g, cv.ROTATE_90_CLOCKWISE) : g;
  final s = cv.resize(upright, (9, 8), interpolation: cv.INTER_AREA);
  try {
    var h = 0;
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        h = (h << 1) | (s.at<int>(y, x) > s.at<int>(y, x + 1) ? 1 : 0);
      }
    }
    return h;
  } finally {
    s.dispose();
    if (!identical(upright, g)) upright.dispose();
    g.dispose();
  }
}

/// Bits that differ between two [dHash]es.
int hammingDistance(int a, int b) {
  var x = a ^ b, n = 0;
  while (x != 0) {
    x &= x - 1;
    n++;
  }
  return n;
}

/// The card's logo (S10b.8): the largest compact graphic that isn't text.
/// [textBoxes] are the OCR line boxes in pixels (left, top, width, height);
/// they are blanked so only marks and colour shapes remain. Returns a square
/// 256 px JPEG on white, or null when nothing logo-like is found.
Uint8List? extractLogo(Uint8List rectifiedJpeg, List<(double, double, double, double)> textBoxes) {
  final color = cv.imdecode(rectifiedJpeg, cv.IMREAD_COLOR);
  final W = color.cols, H = color.rows;
  final mats = <cv.Mat>[color];
  try {
    final gray = cv.cvtColor(color, cv.COLOR_BGR2GRAY);
    final edges = cv.canny(gray, 60, 160);
    final hsv = cv.cvtColor(color, cv.COLOR_BGR2HSV);
    final sat = cv.inRange(
      hsv,
      cv.Mat.fromScalar(1, 1, cv.MatType.CV_8UC3, cv.Scalar(0, 70, 50, 0)),
      cv.Mat.fromScalar(1, 1, cv.MatType.CV_8UC3, cv.Scalar(180, 255, 255, 0)),
    );
    final mask = cv.bitwiseOR(edges, sat);
    mats.addAll([gray, edges, hsv, sat, mask]);
    for (final (l, t, w, h) in textBoxes) {
      final pad = math.max(4.0, h * 0.15);
      cv.rectangle(
        mask,
        cv.Rect(
          (l - pad).round().clamp(0, W - 1),
          (t - pad).round().clamp(0, H - 1),
          (w + 2 * pad).round().clamp(1, W),
          (h + 2 * pad).round().clamp(1, H),
        ),
        cv.Scalar.black,
        thickness: -1,
      );
    }
    // Ignore a thin frame round the edge (printed borders, card edges).
    final edge = (math.min(W, H) * 0.03).round();
    cv.rectangle(mask, cv.Rect(0, 0, W, H), cv.Scalar.black, thickness: edge * 2);
    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (15, 15));
    final merged = cv.dilate(mask, kernel);
    mats.addAll([kernel, merged]);
    final (contours, _) = cv.findContours(merged, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
    final minSide = math.min(W, H);
    cv.Rect? best;
    var bestScore = 0.0;
    for (final c in contours) {
      final r = cv.boundingRect(c);
      final area = r.width * r.height;
      if (area < W * H * 0.006) continue; // specks
      // Background blocks and stripes; a tall narrow illustration (a mascot
      // down one side) is still a logo.
      if (r.width > W * 0.6 || r.height > H * 0.92 || (r.height > H * 0.7 && r.width > W * 0.45)) continue;
      if (math.min(r.width, r.height) < minSide * 0.06) continue; // rules and underlines
      final aspect = r.width / r.height;
      if (aspect > 4 || aspect < 0.25) continue;
      // How much of the box is actually marked (a real logo is dense).
      final roi = mask.region(r);
      final fill = cv.countNonZero(roi) / area;
      roi.dispose();
      if (fill < 0.04) continue;
      // A plain patch of card (paper texture, a faint fold) is not a logo:
      // fall back to initials (phone test F25).
      final grayRoi = gray.region(r);
      final (_, sd) = cv.meanStdDev(grayRoi);
      final satRoi = sat.region(r);
      final colourful = cv.countNonZero(satRoi) / area;
      grayRoi.dispose();
      satRoi.dispose();
      if (sd.val1 < 18) continue;
      // A QR code: square, dense black-and-white modules, no colour (F27).
      if (aspect > 0.8 && aspect < 1.25 && fill > 0.35 && colourful < 0.05 && sd.val1 > 80) continue;
      final score = area * (1 - (aspect - 1).abs().clamp(0, 3) / 4) * (0.5 + fill);
      if (score > bestScore) {
        bestScore = score;
        best = r;
      }
    }
    if (best == null) return null;
    final side = (math.max(best.width, best.height) * 1.15).round();
    final cx = best.x + best.width / 2, cy = best.y + best.height / 2;
    final square = cv.Mat.fromScalar(side, side, cv.MatType.CV_8UC3, cv.Scalar.all(255));
    mats.add(square);
    final x0 = (cx - side / 2).round(), y0 = (cy - side / 2).round();
    final sx = math.max(0, x0), sy = math.max(0, y0);
    final ex = math.min(W, x0 + side), ey = math.min(H, y0 + side);
    if (ex - sx < 8 || ey - sy < 8) return null;
    final src = color.region(cv.Rect(sx, sy, ex - sx, ey - sy));
    final dst = square.region(cv.Rect(sx - x0, sy - y0, ex - sx, ey - sy));
    src.copyTo(dst);
    final out = cv.resize(square, (256, 256), interpolation: cv.INTER_AREA);
    mats.addAll([src, dst, out]);
    final (_, jpg) = cv.imencode('.jpg', out, params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 90]));
    return jpg;
  } finally {
    for (final m in mats) {
      m.dispose();
    }
  }
}
