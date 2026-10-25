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
  final DateTime born;
  bool stuckLogged = false;
  double sharpness;
  int tries = 0;
  DateTime? missedAt;

  /// Shown on the card: "Done", "Already in queue", "Not a card?".
  String? note;

  /// Read as nothing: forgotten soon after, never captured.
  bool notCard = false;

  /// Why this card isn't being captured yet ("moving", "blurry", "edge",
  /// "shape", "busy", "wait"...), set by [SweepTracker.next]. Shown on the card
  /// in the debug overlay (long-press the counter) so a phone test can tell why a
  /// card is skipped.
  String? wait;

  SweepTrack(this.id, this.quad, DateTime now, this.sharpness) : seen = now, steadySince = now, born = now;
}

/// Where sweep logs go (logcat, tag `flutter`, prefix `sweep:`). Tests swap it.
void Function(String) sweepLog = _printSweep;
// ignore: avoid_print
void _printSweep(String m) => print('sweep: $m');

/// Matches card outlines between preview frames and decides when to capture.
/// Pure logic: no camera, no Flutter, so it is unit-tested with synthetic quads.
/// A stray outline is a ghost when it is under this share of the median card...
const sweepGhostRatio = 0.25;

/// ...and under this share of the whole view.
const sweepGhostFrame = 0.03;

/// An outline is drawn only when it covers this share of the view and has print
/// on it ([sweepDrawTexture] and up, or 8% of the sharpest card in view).
const sweepMinArea = 0.03;
const sweepDrawTexture = 8.0;

/// A lone small card (0.4% to 3% of the view) is kept only when it is clearly
/// printed: bare table, glare and printed boxes score far below this.
const sweepSmallArea = 0.004;
const sweepSmallTexture = 30.0;

/// An inner outline (logo box, colour band, illustration) is part of the card
/// that holds its centre when it is under this share of that card.
const sweepInnerRatio = 0.4;

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

  /// The still is only taken while the whole view drifts slower than this share
  /// of the long side per second: a phone still moving blurs the still (third
  /// sweep test).
  final double maxViewMotion;

  SweepTracker({
    this.maxViewMotion = 0.2,
    this.minAspect = 1.35,
    this.maxAspect = 2.0,
    this.minTexture = 4,
    this.matchDistance = 0.18,
    this.steadyTolerance = 0.035,
    this.steadyFor = const Duration(milliseconds: 300),
    this.minSharpness = 15,
    this.softAfter = const Duration(milliseconds: 600),
    this.forget = const Duration(milliseconds: 1200),
    this.retryAfter = const Duration(seconds: 2),
    this.maxTries = 3,
  });

  final tracks = <SweepTrack>[];
  int _nextId = 1;

  /// (old track id, new track id): an enclosing card appeared around a track that
  /// was a logo box or band. The old one is gone from [tracks]; the screen takes
  /// these with [takeSuperseded] to replace the junk queue entry it may have made.
  final _superseded = <(int, int)>[];
  List<(int, int)> takeSuperseded() {
    final out = [..._superseded];
    _superseded.clear();
    return out;
  }

  /// How the whole view is drifting, in frame pixels per millisecond: the
  /// median movement of the cards matched in the last frame. Outlines are moved
  /// by it between analysed frames so they glide with the cards.
  Pt velocity = const Pt(0, 0);
  DateTime? _lastUpdate;

  /// Where to draw [t] at [now]: its last outline, carried along by a damped
  /// [velocity] for at most one frame interval ([maxGlide]). Only a card seen
  /// in the latest frame glides; one out of view holds still and fades. The
  /// next detection snaps it back. Longer predictions overshot and drifted the
  /// overlays off their cards (third sweep test).
  ///
  /// Only the plain outline of a card still waiting to be read glides. A card
  /// being read, a done card and a missed one sit exactly on the latest detection:
  /// a filled green or amber patch pushed ahead of a card that is being moved
  /// jumped back on every frame and looked as if it lagged (0.7.4).
  Quad displayQuad(SweepTrack t, DateTime now) {
    if (t.state != SweepState.found) return t.quad;
    if (_lastUpdate == null || t.seen != _lastUpdate) return t.quad;
    final ms = now.difference(t.seen).inMilliseconds.clamp(0, maxGlide.inMilliseconds);
    if (ms == 0 || (velocity.x == 0 && velocity.y == 0)) return t.quad;
    final dx = velocity.x * ms * 0.6, dy = velocity.y * ms * 0.6;
    return Quad([for (final p in t.quad.corners) Pt(p.x + dx, p.y + dy)]);
  }

  /// About one analysed-frame interval.
  static const maxGlide = Duration(milliseconds: 120);

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
    // Thin slivers along the table edge, wedges and outlines filling the view
    // are never cards: not outlined, never captured (third sweep test).
    final keep = [
      for (var i = 0; i < quads.length; i++)
        if (sweepShapeOk(quads[i], width: width, height: height)) i,
    ];
    if (keep.length != quads.length) {
      sharpness = [for (final i in keep) i < sharpness.length ? sharpness[i] : 0.0];
      quads = [for (final i in keep) quads[i]];
    }
    // Ghosts on bare table: no print, or too small to be a card (fifth test).
    if (quads.isNotEmpty) {
      final top = sharpness.isEmpty ? 0.0 : sharpness.reduce(math.max);
      final bar = math.max(sweepDrawTexture, top * 0.08);
      final ok = [
        for (var i = 0; i < quads.length; i++)
          if (sweepDrawOk(quads[i], i < sharpness.length ? sharpness[i] : 0, width: width, height: height, bar: bar)) i,
      ];
      if (ok.length != quads.length) {
        sharpness = [for (final i in ok) i < sharpness.length ? sharpness[i] : 0.0];
        quads = [for (final i in ok) quads[i]];
      }
    }
    // A logo box, band or illustration inside a card is not a card, whichever
    // was found first (fifth test: Maxpak's logo box was captured as a card).
    if (quads.length > 1) {
      final inside = <int>{
        for (var i = 0; i < quads.length; i++)
          for (var j = 0; j < quads.length; j++)
            if (i != j && quads[i].area < quads[j].area * sweepInnerRatio && pointInQuad(quads[j], centre(quads[i]))) i,
      };
      if (inside.isNotEmpty) {
        final ok = [
          for (var i = 0; i < quads.length; i++)
            if (!inside.contains(i)) i,
        ];
        sharpness = [for (final i in ok) i < sharpness.length ? sharpness[i] : 0.0];
        quads = [for (final i in ok) quads[i]];
      }
    }
    // Small stray outlines beside real cards (printed boxes, glare) are ghosts:
    // much smaller than the median card and under 3% of the view (fourth test).
    if (quads.length > 1) {
      final areas = [for (final q in quads) q.area]..sort();
      final median = areas[areas.length ~/ 2];
      final ghost = <int>{
        for (var i = 0; i < quads.length; i++)
          if (quads[i].area < median * sweepGhostRatio && quads[i].area < width * height * sweepGhostFrame) i,
      };
      if (ghost.isNotEmpty) {
        final ok = [
          for (var i = 0; i < quads.length; i++)
            if (!ghost.contains(i)) i,
        ];
        sharpness = [for (final i in ok) i < sharpness.length ? sharpness[i] : 0.0];
        quads = [for (final i in ok) quads[i]];
      }
    }
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
      final fresh = SweepTrack(_nextId++, quads[q], now, q < sharpness.length ? sharpness[q] : 0);
      // Tracks that were only a box inside this card: replaced by the card.
      for (var t = tracks.length - 1; t >= 0; t--) {
        final old = tracks[t];
        if (usedTracks.contains(t) || old.quad.area >= fresh.quad.area * sweepInnerRatio) continue;
        if (!pointInQuad(fresh.quad, centre(old.quad))) continue;
        sweepLog('track ${old.id} (${old.state.name}) was inside new card ${fresh.id}: replaced');
        if (old.state == SweepState.done) doneCount = math.max(0, doneCount - 1);
        _superseded.add((old.id, fresh.id));
        tracks.removeAt(t);
        // Keep the matched-track indexes pointing at the same tracks.
        final shifted = {for (final u in usedTracks) u > t ? u - 1 : u};
        usedTracks
          ..clear()
          ..addAll(shifted);
      }
      tracks.add(fresh);
    }
    // A card being read keeps its track while out of view, so its result can land.
    // A "Not a card?" patch shows for a moment, then goes.
    tracks.removeWhere((t) {
      final gone =
          (t.state != SweepState.reading && now.difference(t.seen) > forget) ||
          (t.notCard && t.missedAt != null && now.difference(t.missedAt!) > const Duration(milliseconds: 1500));
      if (gone && t.state != SweepState.done && !t.notCard) {
        sweepLog(
          'track ${t.id} dropped after ${now.difference(t.born).inMilliseconds} ms, ${t.state.name}, last reason: ${t.wait ?? 'none yet'}',
        );
      }
      return gone;
    });
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
  SweepTrack? next({required double width, required double height, required DateTime now, bool busy = false}) {
    final edge = math.max(width, height) * 0.01;
    final moving = viewMotion(math.max(width, height)) > maxViewMotion;
    SweepTrack? best;
    for (final t in tracks) {
      t.wait = _blocked(t, width: width, height: height, now: now, edge: edge, moving: moving, busy: busy);
      if (t.wait != null && !t.stuckLogged && t.state == SweepState.found && now.difference(t.born).inSeconds >= 5) {
        t.stuckLogged = true;
        sweepLog('track ${t.id} not captured after 5 s: ${t.wait}');
      }
      if (t.wait != null) continue;
      if (best == null || t.quad.area > best.quad.area) best = t;
    }
    return best;
  }

  /// Why [t] can't be captured in this frame, or null when it can.
  String? _blocked(
    SweepTrack t, {
    required double width,
    required double height,
    required DateTime now,
    required double edge,
    required bool moving,
    required bool busy,
  }) {
    if (t.seen != now) return 'out of view';
    if (t.state == SweepState.done || t.state == SweepState.reading) return 'read';
    if (t.state == SweepState.missed) {
      if (t.tries >= maxTries) return 'gave up';
      if (t.missedAt != null && now.difference(t.missedAt!) < retryAfter) return 'cooldown';
    }
    if (!cardLike(t.quad, width: width, height: height)) return 'shape';
    final cut = t.quad.corners.any((p) => p.x < edge || p.y < edge || p.x > width - edge || p.y > height - edge);
    if (cut) return 'edge';
    if (t.sharpness < minTexture) return 'no print'; // a blank patch
    // Mostly on top of a card already read: the same card, outlined again.
    if (tracks.any((o) => o.state == SweepState.done && !identical(o, t) && _overlap(o.quad, t.quad) > 0.5)) {
      return 'read';
    }
    if (moving) return 'moving';
    final held = now.difference(t.steadySince);
    if (held < steadyFor) return 'settling';
    if (t.sharpness < minSharpness && held < softAfter) return 'blurry';
    if (busy) return 'waiting for photo';
    return null;
  }

  /// How fast the whole view moves: share of [long] per second.
  double viewMotion(double long) =>
      long <= 0 ? 0 : math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y) * 1000 / long;

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

/// True when [q] can be a card seen at an angle in a [width] x [height] frame:
/// convex, long side at most 2.4 times the short side, short side at least 4%
/// of the frame's long side, every corner between 55 and 125 degrees, and at
/// most 60% of the frame.
bool sweepShapeOk(Quad q, {required double width, required double height}) {
  if (!q.isConvex) return false;
  final short = q.shortSide, long = q.longSide;
  if (short <= 0 || long / short > 2.4) return false;
  if (short < math.max(width, height) * 0.04) return false;
  if (q.area > width * height * 0.6) return false;
  for (var i = 0; i < 4; i++) {
    final a = q.corners[(i + 3) % 4], b = q.corners[i], c = q.corners[(i + 1) % 4];
    final v1 = a - b, v2 = c - b;
    final len = v1.length * v2.length;
    if (len == 0) return false;
    final cos = ((v1.x * v2.x + v1.y * v2.y) / len).clamp(-1.0, 1.0);
    final deg = math.acos(cos) * 180 / math.pi;
    if (deg < 55 || deg > 125) return false;
  }
  return true;
}

/// True when [q] should be drawn and tracked: big enough and printed enough to
/// be a card, not bare table. [bar] is the print level (sharpness) it needs.
bool sweepDrawOk(
  Quad q,
  double sharpness, {
  required double width,
  required double height,
  double bar = sweepDrawTexture,
}) {
  final share = q.area / (width * height);
  if (share >= sweepMinArea) return sharpness >= bar;
  return share >= sweepSmallArea && sharpness >= math.max(sweepSmallTexture, bar);
}

/// True when [p] lies inside the convex quad [q].
bool pointInQuad(Quad q, Pt p) {
  double? sign;
  for (var i = 0; i < 4; i++) {
    final a = q.corners[i], b = q.corners[(i + 1) % 4];
    final cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
    if (cross == 0) continue;
    sign ??= cross.sign;
    if (cross.sign != sign) return false;
  }
  return true;
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
