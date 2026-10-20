/// Capture quality gates (deep dive §2.1). Thresholds are starting values to
/// tune on real cards; they never block a capture, they flag it for review.
class Gates {
  static const minAreaRatio = 0.45; // card area / frame area
  static const minSharpness = 80.0; // variance of Laplacian on the card, 1000 px long edge
  static const maxGlare = 0.015; // fraction of card area at luminance >= 250
  static const minExposure = 70.0; // mean luminance 0..255
  static const maxExposure = 200.0;
  static const minRectifiedLong = 1400; // px
  static const steadyMs = 400;
}

/// Measurements for one frame or still.
class FrameMetrics {
  final bool cardFound;
  final bool cardCutOff; // a corner touches the frame edge
  final double areaRatio;

  /// Null on live preview frames: a downscaled frame can't judge focus, so
  /// preview uses steadiness and the still is checked for sharpness.
  final double? sharpness;
  final double glare;
  final double exposure;

  const FrameMetrics({
    required this.cardFound,
    this.cardCutOff = false,
    this.areaRatio = 0,
    this.sharpness,
    this.glare = 0,
    this.exposure = 128,
  });
}

/// Problems, in the order the live hint shows them (one at a time).
enum QualityIssue {
  noCard('Point the camera at a card'),
  cutOff('Card cut off'),
  tooSmall('Move closer'),
  blurry('Hold steady'),
  glare('Glare, tilt the card'),
  dark('More light'),
  bright('Too bright');

  final String hint;
  const QualityIssue(this.hint);

  /// Short chip on a queued card ("Blurry", "Glare").
  String get chip => switch (this) {
    noCard => 'No card found',
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
    if (m.areaRatio < Gates.minAreaRatio) QualityIssue.tooSmall,
    if (m.sharpness != null && m.sharpness! < Gates.minSharpness) QualityIssue.blurry,
    if (m.glare >= Gates.maxGlare) QualityIssue.glare,
    if (m.exposure < Gates.minExposure) QualityIssue.dark,
    if (m.exposure > Gates.maxExposure) QualityIssue.bright,
  ];
}

/// Decides when to auto-capture: a card passes every gate and its outline has
/// stayed put for [Gates.steadyMs].
class AutoCapture {
  DateTime? _steadySince;
  bool _fired = false;

  /// Feed one analysed frame. Returns true once, when it is time to shoot.
  bool update({required bool clean, required bool steady, required DateTime now}) {
    if (_fired) return false;
    if (!clean || !steady) {
      _steadySince = null;
      return false;
    }
    _steadySince ??= now;
    if (now.difference(_steadySince!).inMilliseconds >= Gates.steadyMs) {
      _fired = true;
      return true;
    }
    return false;
  }

  void reset() {
    _steadySince = null;
    _fired = false;
  }
}
