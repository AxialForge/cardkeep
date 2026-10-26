/// Capture quality gates (deep dive §2.1). Thresholds are starting values to
/// tune on real cards; they never block a capture, they flag it for review.
class Gates {
  /// Card's long side / the frame's short side. In portrait the short side is
  /// the screen width, so 0.5 = the card spans half the view: close enough for a
  /// 1400 px card from a 12 MP photo, far enough to hold comfortably.
  /// (Was "45% of the frame area", which a card can't reach in portrait without
  /// being cut off: the move-closer / cut-off loop reported on 0.2.0.)
  static const minSizeRatio = 0.5;
  static const minSharpness = 80.0; // variance of Laplacian on the card, 1000 px long edge
  /// Fraction of the card that is one big blown-out area (luminance >= 253,
  /// ignoring specular spots under [glareSpotMin] of the card). It only ever
  /// flags a soft hint: a glossy card under bright lights used to say "Glare,
  /// tilt the card" for every reflection (phone test 2026-10-25).
  static const maxGlare = 0.35;
  static const glareSpotMin = 0.08; // a clipped spot smaller than this share of the card is not counted
  static const burstSpecular = 0.03; // clipped share of the card that makes the shutter shoot a burst
  // Exposure uses percentiles, not the mean: a white card is bright and a black
  // card is dark, and both are fine. Text covers only a few percent of a card,
  // so the 1st/99th percentiles are used: too dark = even the brightest 1% is
  // dim; washed out = even the darkest 1% is near white (no ink left).
  static const minHighlight = 90.0; // 99th percentile luminance
  static const maxShadow = 225.0; // 1st percentile luminance
  static const minRectifiedLong = 1400; // px
  static const steadyMs = 400; // clean card, steady this long: capture
  static const softCaptureMs = 900; // steady this long with only soft issues (glare, light): capture anyway, flagged
  static const steadyTolerance = 0.035; // corner movement allowed between frames, fraction of frame width
}

/// Measurements for one frame or still.
class FrameMetrics {
  final bool cardFound;
  final bool cardCutOff; // a corner touches the frame edge
  final double sizeRatio; // see Gates.minSizeRatio
  /// Null on live preview frames: a downscaled frame can't judge focus, so
  /// preview uses steadiness and the still is checked for sharpness.
  final double? sharpness;

  /// Share of the card that is blown out in big areas (spots under
  /// [Gates.glareSpotMin] ignored): the only glare that flags a hint.
  final double glare;

  /// Share of the card clipped at all, small spots included: decides whether a
  /// burst of photos is worth taking and which of them is best.
  final double specular;
  final double highlight; // 99th percentile luminance
  final double shadow; // 1st percentile luminance

  const FrameMetrics({
    required this.cardFound,
    this.cardCutOff = false,
    this.sizeRatio = 0,
    this.sharpness,
    this.glare = 0,
    this.specular = 0,
    this.highlight = 200,
    this.shadow = 40,
  });
}

/// Problems, in the order the live hint shows them (one at a time).
enum QualityIssue {
  noCard('Point the camera at a card'),
  cutOff('Card cut off'),
  tooSmall('Move closer'),
  blurry('Hold steady'),
  glare('Tilt the card a little'),
  dark('More light'),
  bright('Too bright');

  final String hint;
  const QualityIssue(this.hint);

  /// Soft issues don't stop auto-capture for long: the card is captured
  /// anyway after [Gates.softCaptureMs] and flagged.
  bool get soft => this == glare || this == dark || this == bright || this == blurry;

  /// Short chip on a queued card ("Blurry", "Glare").
  String get chip => switch (this) {
    noCard => 'No edges found',
    cutOff => 'Cut off',
    tooSmall => 'Small',
    blurry => 'Blurry',
    glare => 'Glare',
    dark => 'Dark',
    bright => 'Overexposed',
  };
}

List<QualityIssue> assess(FrameMetrics m) {
  if (!m.cardFound) return const [QualityIssue.noCard];
  return [
    if (m.cardCutOff) QualityIssue.cutOff,
    if (m.sizeRatio < Gates.minSizeRatio) QualityIssue.tooSmall,
    if (m.sharpness != null && m.sharpness! < Gates.minSharpness) QualityIssue.blurry,
    if (m.glare >= Gates.maxGlare) QualityIssue.glare,
    if (m.highlight < Gates.minHighlight) QualityIssue.dark,
    if (m.shadow > Gates.maxShadow) QualityIssue.bright,
  ];
}

/// Decides when to auto-capture. Forgiving on purpose (0.2.0 felt clunky):
/// one bad frame doesn't restart the count, and soft problems (glare, light)
/// only delay the shot instead of blocking it.
class AutoCapture {
  DateTime? _since;
  int _misses = 0;
  bool _fired = false;

  /// Feed one analysed frame: its [issues] and whether the outline held still
  /// since the previous frame. Returns true once, when it is time to shoot.
  bool update({required List<QualityIssue> issues, required bool steady, required DateTime now}) {
    if (_fired) return false;
    final blocked = issues.any((i) => !i.soft);
    if (blocked || !steady) {
      // Tolerate a single flickery frame (detection or a small hand movement).
      if (++_misses >= 2) _since = null;
      return false;
    }
    _misses = 0;
    _since ??= now;
    final held = now.difference(_since!).inMilliseconds;
    final soft = issues.isNotEmpty;
    if (held >= (soft ? Gates.softCaptureMs : Gates.steadyMs)) {
      _fired = true;
      return true;
    }
    return false;
  }

  /// 0..1 towards the next automatic shot (for the progress ring).
  double progress({required bool soft, required DateTime now}) {
    if (_since == null || _fired) return 0;
    final need = soft ? Gates.softCaptureMs : Gates.steadyMs;
    return (now.difference(_since!).inMilliseconds / need).clamp(0.0, 1.0);
  }

  void reset() {
    _since = null;
    _misses = 0;
    _fired = false;
  }
}
