import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'geometry.dart';
import 'quality.dart';

/// Greyscale pixels, row-major, no row padding (camera Y plane or a decoded still).
class GrayFrame {
  final Uint8List bytes;
  final int width, height;
  const GrayFrame(this.bytes, this.width, this.height);
}

/// What the detector found in one frame. Quads are in the frame's pixel space.
class Detection {
  final Quad? card; // best single card
  final List<Quad> cards; // every separate card (pile mode)
  final FrameMetrics metrics;
  const Detection(this.card, this.cards, this.metrics);

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
  try {
    return _detectMat(gray);
  } finally {
    gray.dispose();
  }
}

Detection _detectMat(cv.Mat gray) {
  final scale = _detectLong / math.max(gray.cols, gray.rows);
  final small = scale < 1
      ? cv.resize(gray, ((gray.cols * scale).round(), (gray.rows * scale).round()), interpolation: cv.INTER_AREA)
      : gray.clone();
  final s = scale < 1 ? scale : 1.0;
  try {
    final quads = _findQuads(small);
    final frameArea = (small.cols * small.rows).toDouble();
    final best = pickCardQuad(quads, frameArea: frameArea, minAreaRatio: 0.02);
    final all = _separateCards(quads, frameArea);
    if (best == null) {
      return const Detection(null, [], FrameMetrics(cardFound: false));
    }
    final metrics = _measure(small, best, frameArea);
    return Detection(best.scaled(1 / s), [for (final q in all) q.scaled(1 / s)], metrics);
  } finally {
    small.dispose();
  }
}

/// Card outlines. A second, more sensitive pass (contrast stretched, lower
/// edge thresholds) runs when the first finds nothing: a small card, or a
/// white card on a light table (phone test F23).
List<Quad> _findQuads(cv.Mat small) {
  final first = _findQuadsPass(small, 40, 120);
  if (pickCardQuad(first, frameArea: (small.cols * small.rows).toDouble(), minAreaRatio: 0.02) != null) return first;
  final eq = cv.equalizeHist(small);
  try {
    return [...first, ..._findQuadsPass(eq, 15, 45)];
  } finally {
    eq.dispose();
  }
}

List<Quad> _findQuadsPass(cv.Mat small, double lo, double hi) {
  final blur = cv.gaussianBlur(small, (5, 5), 0);
  final edges = cv.canny(blur, lo, hi);
  final kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
  final closed = cv.morphologyEx(edges, cv.MORPH_CLOSE, kernel, iterations: 2);
  final (contours, hierarchy) = cv.findContours(closed, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);
  final frameArea = small.cols * small.rows;
  final out = <Quad>[];
  for (final c in contours) {
    // Small on purpose: a distant card must still be found to get "Move closer".
    if (cv.contourArea(c) < frameArea * 0.015) continue;
    final approx = cv.approxPolyDP(c, 0.02 * cv.arcLength(c, true), true);
    if (approx.length == 4) {
      out.add(Quad([for (final p in approx) Pt(p.x.toDouble(), p.y.toDouble())]));
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
    final (_, bright) = cv.threshold(card, 252, 255, cv.THRESH_BINARY);
    final glare = cv.countNonZero(bright) / (card.cols * card.rows);
    final (shadow, highlight) = _percentiles(card);
    bright.dispose();
    return FrameMetrics(
      cardFound: true,
      cardCutOff: cutOff,
      sizeRatio: q.longSide / math.min(small.cols, small.rows),
      glare: glare,
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
}) {
  final clean = _cleanOriginal(jpeg);
  final color = clean.color;
  final gray = cv.cvtColor(color, cv.COLOR_BGR2GRAY);
  try {
    final frameArea = (color.cols * color.rows).toDouble();
    List<Quad> quads;
    var manual = false;
    if (corners != null) {
      // Corners are set on the stored original; one from before originals were
      // downscaled is bigger than this copy, so scale them to match.
      final big = cv.imdecode(jpeg, cv.IMREAD_REDUCED_GRAYSCALE_8);
      final fullLong = math.max(big.cols, big.rows) * 8;
      big.dispose();
      final f = math.max(color.cols, color.rows) / fullLong;
      quads = [f < 0.95 ? corners.scaled(f) : corners];
      manual = true;
    } else {
      final d = _detectMat(gray);
      quads = allCards && d.cards.length > 1 ? d.cards : [if (d.card != null) d.card!];
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
      final size = manual && corners == null
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
      final metrics = _measureRectified(
        rectGray,
        q,
        frameArea,
        color.cols,
        color.rows,
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
    gray.dispose();
    color.dispose();
  }
}

FrameMetrics _measureRectified(cv.Mat rectGray, Quad q, double frameArea, int w, int h, {required bool manual}) {
  final scale = 1000 / math.max(rectGray.cols, rectGray.rows);
  final norm = cv.resize(rectGray, (
    (rectGray.cols * scale).round(),
    (rectGray.rows * scale).round(),
  ), interpolation: cv.INTER_AREA);
  final lap = cv.laplacian(norm, cv.MatType.CV_64F);
  final (_, std) = cv.meanStdDev(lap);
  final (_, bright) = cv.threshold(norm, 252, 255, cv.THRESH_BINARY);
  final edge = math.max(w, h) * 0.01;
  final m = FrameMetrics(
    cardFound: !manual,
    cardCutOff: !manual && q.corners.any((p) => p.x < edge || p.y < edge || p.x > w - edge || p.y > h - edge),
    // A still is judged on resolution, not framing: big enough when the card
    // reaches the 1400 px gate without upscaling.
    sizeRatio: q.longSide / Gates.minRectifiedLong * Gates.minSizeRatio,
    sharpness: std.val1 * std.val1,
    glare: cv.countNonZero(bright) / (norm.cols * norm.rows),
    highlight: _percentiles(norm).$2,
    shadow: _percentiles(norm).$1,
  );
  norm.dispose();
  lap.dispose();
  bright.dispose();
  return m;
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
/// how sharp each looks (variance of Laplacian on its box, ~640 px frame).
class SweepFrame {
  final List<Quad> cards; // in the frame's pixel space
  final List<double> sharpness;
  final int width, height;
  const SweepFrame(this.cards, this.sharpness, this.width, this.height);
}

/// Finds all cards in a preview frame and measures each one's sharpness.
/// Pure function for compute().
SweepFrame sweepDetect(GrayFrame f) {
  final gray = cv.Mat.fromVec(cv.VecUChar.fromList(f.bytes), rows: f.height, cols: f.width, type: cv.MatType.CV_8UC1);
  final scale = _detectLong / math.max(gray.cols, gray.rows);
  final small = scale < 1
      ? cv.resize(gray, ((gray.cols * scale).round(), (gray.rows * scale).round()), interpolation: cv.INTER_AREA)
      : gray.clone();
  final s = scale < 1 ? scale : 1.0;
  try {
    final cards = _separateCards(_findQuads(small), (small.cols * small.rows).toDouble());
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
    return SweepFrame([for (final q in cards) q.scaled(1 / s)], sharp, f.width, f.height);
  } finally {
    small.dispose();
    gray.dispose();
  }
}

/// Cuts one card out of a full-resolution still for Sweep mode. [quad] is the
/// card in a preview frame of [frameWidth] x [frameHeight] (portrait, same
/// field of view as the still); a generous margin covers the small offset
/// between preview and still, and the pipeline then finds the exact edges.
Uint8List cropForSweep((Uint8List jpeg, Quad quad, int frameWidth, int frameHeight) a) {
  final (jpeg, quad, fw, fh) = a;
  var m = cv.imdecode(jpeg, cv.IMREAD_COLOR); // applies EXIF orientation
  if (m.isEmpty) throw const FormatException('Not an image');
  if ((m.cols > m.rows) != (fw > fh)) {
    final r = cv.rotate(m, cv.ROTATE_90_CLOCKWISE);
    m.dispose();
    m = r;
  }
  final sx = m.cols / fw, sy = m.rows / fh;
  final xs = quad.corners.map((p) => p.x * sx), ys = quad.corners.map((p) => p.y * sy);
  final l = xs.reduce(math.min), t = ys.reduce(math.min), r = xs.reduce(math.max), b = ys.reduce(math.max);
  final padX = (r - l) * 0.18, padY = (b - t) * 0.18;
  final x = (l - padX).round().clamp(0, m.cols - 1), y = (t - padY).round().clamp(0, m.rows - 1);
  final w = ((r + padX).round() - x).clamp(1, m.cols - x), h = ((b + padY).round() - y).clamp(1, m.rows - y);
  final roi = m.region(cv.Rect(x, y, w, h));
  final (_, out) = cv.imencode('.jpg', roi, params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 92]));
  roi.dispose();
  m.dispose();
  return out;
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
