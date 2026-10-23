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

  /// Shown on the card when done: "Done" or "Already in queue".
  String? note;

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

  SweepTracker({
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
    for (final (_, t, q) in pairs) {
      if (usedTracks.contains(t) || usedQuads.contains(q)) continue;
      usedTracks.add(t);
      usedQuads.add(q);
      final track = tracks[t];
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
    tracks.removeWhere((t) => t.state != SweepState.reading && now.difference(t.seen) > forget);
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
      final cut = t.quad.corners.any((p) => p.x < edge || p.y < edge || p.x > width - edge || p.y > height - edge);
      if (cut) continue;
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

  void reset() {
    tracks.clear();
    doneCount = 0;
  }
}

Pt centre(Quad q) =>
    Pt(q.corners.map((p) => p.x).reduce((a, b) => a + b) / 4, q.corners.map((p) => p.y).reduce((a, b) => a + b) / 4);
