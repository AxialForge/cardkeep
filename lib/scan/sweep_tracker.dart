import 'dart:math' as math;

import 'geometry.dart';

/// Sweep scan (roadmap S14c): cards laid out on a table, the phone moved over
/// them. Each card found in the preview gets a track that follows it from frame
/// to frame; a track is captured once when it is steady and sharp, read in the
/// background, and then stays done.
enum SweepState {
  /// Outlined: seen, not read yet.
  found,

  /// Captured; the background reader has it.
  reading,

  /// Read and in the review queue (or saved).
  done,

  /// Could not be read; hover over it again.
  missed,
}

class SweepTrack {
  final int id;
  Quad quad;
  SweepState state = SweepState.found;
  DateTime seen;
  DateTime steadySince;
  double sharpness;
  int tries = 0;
  DateTime? missedAt;

  /// Shown on the card: "Done", "Already in queue", "Not a card?".
  String? note;

  /// Read as nothing: forgotten soon after, never captured.
  bool notCard = false;

  SweepTrack(this.id, this.quad, DateTime now, this.sharpness) : seen = now, steadySince = now;
}

/// Matches card outlines between preview frames and decides when to capture.
/// Pure logic: no camera, no Flutter, so it is unit-tested with synthetic quads.
class SweepTracker {
  /// A detection belongs to a track when its centre is within this share of
  /// the frame's long side (the phone moves a little between analysed frames).
  final double matchDistance;

  /// Corners moving less than this share of the long side count as steady.
  final double steadyTolerance;

  /// How long a card must stay steady before it is captured.
  final Duration steadyFor;

  /// Minimum variance of Laplacian on the card in the preview. A card that
  /// stays steady for [softAfter] is captured anyway (the still is sharper than
  /// the preview, and the pipeline flags a blurry result).
  final double minSharpness;
  final Duration softAfter;

  /// Tracks not seen for this long are dropped (the card left the view).
  final Duration forget;

  /// A missed card is retried after this long, at most [maxTries] times.
  final Duration retryAfter;
  final int maxTries;

  /// Shape gate for capturing (outlines are drawn for every quad).
  final double minAspect, maxAspect;

  /// Below this sharpness (variance of Laplacian on the card) there is no
  /// print to read, however long it is held: a blank mat or table patch.
  final double minTexture;

  SweepTracker({
    this.minAspect = 1.35,
    this.maxAspect = 2.0,
    this.minTexture = 4,
    this.matchDistance = 0.18,
    this.steadyTolerance = 0.025,
    this.steadyFor = const Duration(milliseconds: 300),
    this.minSharpness = 25,
    this.softAfter = const Duration(milliseconds: 900),
    this.forget = const Duration(milliseconds: 1200),
    this.retryAfter = const Duration(seconds: 2),
    this.maxTries = 3,
  });

  final tracks = <SweepTrack>[];
  int _nextId = 1;

  /// How the whole view is drifting, in frame pixels per millisecond: the
  /// median movement of the cards matched in the last frame. Outlines are moved
  /// by it between analysed frames so they glide with the cards.
  Pt velocity = const Pt(0, 0);
  DateTime? _lastUpdate;

  /// Where to draw [t] at [now]: its last outline carried along by [velocity]
  /// (at most 400 ms ahead, so a stopped phone doesn't drift the outlines).
  Quad displayQuad(SweepTrack t, DateTime now) {
    final ms = now.difference(t.seen).inMilliseconds.clamp(0, 400);
    if (ms == 0 || (velocity.x == 0 && velocity.y == 0)) return t.quad;
    final dx = velocity.x * ms, dy = velocity.y * ms;
    return Quad([for (final p in t.quad.corners) Pt(p.x + dx, p.y + dy)]);
  }

  /// 1 while a card is in view, fading to 0 over the time before it is forgotten.
  double opacity(SweepTrack t, DateTime now) {
    final age = now.difference(t.seen).inMilliseconds;
    const solid = 300;
    if (age <= solid) return 1;
    return (1 - (age - solid) / (forget.inMilliseconds - solid)).clamp(0.0, 1.0);
  }

  /// Cards read this session, including ones that have since left the view.
  int doneCount = 0;

  /// Done cards still in view plus everything else in view, plus done cards
  /// that left the view: "7 of 9 done".
  int get total => doneCount + tracks.where((t) => t.state != SweepState.done).length;

  /// Folds one analysed frame in. [quads] are in a frame [width] x [height];
  /// [sharpness] has one value per quad.
  void update(
    List<Quad> quads,
    List<double> sharpness, {
    required double width,
    required double height,
    required DateTime now,
  }) {
    final long = math.max(width, height);
    final maxDist = matchDistance * long;
    final pairs = <(double, int, int)>[]; // distance, track index, quad index
    for (var t = 0; t < tracks.length; t++) {
      for (var q = 0; q < quads.length; q++) {
        final d = centre(tracks[t].quad).distanceTo(centre(quads[q]));
        final area = quads[q].area / math.max(tracks[t].quad.area, 1);
        if (d <= maxDist && area > 0.5 && area < 2) pairs.add((d, t, q));
      }
    }
    pairs.sort((a, b) => a.$1.compareTo(b.$1));
    final usedTracks = <int>{}, usedQuads = <int>{};
    final moves = <(Pt, Pt)>[];
    for (final (_, t, q) in pairs) {
      if (usedTracks.contains(t) || usedQuads.contains(q)) continue;
      usedTracks.add(t);
      usedQuads.add(q);
      final track = tracks[t];
      moves.add((centre(track.quad), centre(quads[q])));
      if (!sameQuad(track.quad, quads[q], steadyTolerance * long)) track.steadySince = now;
      track
        ..quad = quads[q]
        ..seen = now
        ..sharpness = q < sharpness.length ? sharpness[q] : 0;
    }
    for (var q = 0; q < quads.length; q++) {
      if (usedQuads.contains(q)) continue;
      tracks.add(SweepTrack(_nextId++, quads[q], now, q < sharpness.length ? sharpness[q] : 0));
    }
    // A card being read keeps its track while out of view, so its result can land.
    // A "Not a card?" patch shows for a moment, then goes.
    tracks.removeWhere(
      (t) =>
          (t.state != SweepState.reading && now.difference(t.seen) > forget) ||
          (t.notCard && t.missedAt != null && now.difference(t.missedAt!) > const Duration(milliseconds: 1500)),
    );
    final last = _lastUpdate;
    _lastUpdate = now;
    final dt = last == null ? 0 : now.difference(last).inMilliseconds;
    final shift = medianShift(moves);
    if (shift == null || dt <= 0 || dt > 1000) {
      velocity = Pt(velocity.x * 0.5, velocity.y * 0.5);
    } else {
      // Smoothed, so one noisy frame doesn't throw the outlines.
      velocity = Pt(velocity.x * 0.4 + shift.x / dt * 0.6, velocity.y * 0.4 + shift.y / dt * 0.6);
    }
  }

  /// The card to capture now, or null: the biggest one in this frame that is
  /// steady, sharp and fully in view. A done or reading card is never returned,
  /// so no card is read twice.
  SweepTrack? next({required double width, required double height, required DateTime now}) {
    final edge = math.max(width, height) * 0.01;
    SweepTrack? best;
    for (final t in tracks) {
      if (t.seen != now) continue; // not in this frame
      if (t.state == SweepState.done || t.state == SweepState.reading) continue;
      if (t.state == SweepState.missed) {
        if (t.tries >= maxTries) continue;
        if (t.missedAt != null && now.difference(t.missedAt!) < retryAfter) continue;
      }
      final held = now.difference(t.steadySince);
      if (held < steadyFor) continue;
      if (t.sharpness < minSharpness && held < softAfter) continue;
      if (t.sharpness < minTexture) continue; // nothing printed on it
      final cut = t.quad.corners.any((p) => p.x < edge || p.y < edge || p.x > width - edge || p.y > height - edge);
      if (cut) continue;
      if (!cardLike(t.quad, width: width, height: height)) continue;
      // Mostly on top of a card already read: the same card, outlined again.
      if (tracks.any((o) => o.state == SweepState.done && !identical(o, t) && _overlap(o.quad, t.quad) > 0.5)) continue;
      if (best == null || t.quad.area > best.quad.area) best = t;
    }
    return best;
  }

  SweepTrack? byId(int id) => tracks.where((t) => t.id == id).firstOrNull;

  void markReading(int id) {
    final t = byId(id);
    if (t == null) return;
    t
      ..state = SweepState.reading
      ..tries += 1;
  }

  /// [note] is shown on the card, for example "Already in queue".
  void markDone(int id, {String note = 'Done'}) {
    final t = byId(id);
    if (t == null || t.state == SweepState.done) return;
    t
      ..state = SweepState.done
      ..note = note;
    doneCount++;
  }

  void markMissed(int id, DateTime now) {
    final t = byId(id);
    if (t == null || t.state == SweepState.done) return;
    t
      ..state = SweepState.missed
      ..missedAt = now
      ..steadySince = now;
  }

  /// The capture read as nothing (a table patch, a blank mat): shown amber
  /// "Not a card?" for a moment, never captured again, then forgotten.
  void markNotCard(int id, DateTime now) {
    final t = byId(id);
    if (t == null || t.state == SweepState.done) return;
    t
      ..state = SweepState.missed
      ..note = 'Not a card?'
      ..notCard = true
      ..missedAt = now
      ..tries = maxTries;
  }

  /// True when [q] has a card's shape: long side 1.35 to 2.0 times the short
  /// side (3.5 x 2 in is 1.75, 85 x 55 mm 1.55, 90 x 50 mm 1.8), covering
  /// 0.4% to 60% of the frame.
  bool cardLike(Quad q, {required double width, required double height}) {
    final w = q.width, h = q.height;
    final short = math.min(w, h), long = math.max(w, h);
    if (short <= 0) return false;
    final ratio = long / short;
    if (ratio < minAspect || ratio > maxAspect) return false;
    final share = q.area / (width * height);
    return share >= 0.004 && share <= 0.6;
  }

  void reset() {
    tracks.clear();
    doneCount = 0;
  }
}

/// The median movement (x and y separately) of matched cards, from their old
/// centre to their new one; null when nothing matched. The median ignores a
/// card that was matched wrongly.
Pt? medianShift(List<(Pt, Pt)> moves) {
  if (moves.isEmpty) return null;
  double med(List<double> v) {
    v.sort();
    final m = v.length ~/ 2;
    return v.length.isOdd ? v[m] : (v[m - 1] + v[m]) / 2;
  }

  return Pt(med([for (final (a, b) in moves) b.x - a.x]), med([for (final (a, b) in moves) b.y - a.y]));
}

/// Overlap of two quads' bounding boxes, as a share of the smaller box.
double _overlap(Quad a, Quad b) {
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

Pt centre(Quad q) =>
    Pt(q.corners.map((p) => p.x).reduce((a, b) => a + b) / 4, q.corners.map((p) => p.y).reduce((a, b) => a + b) / 4);
