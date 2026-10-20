/// Pure-Dart OCR result, so the parser tests run without a device.
/// The ML Kit adapter converts into this; ground-truth fixtures are stored
/// as this JSON shape.
class OcrLine {
  final String text;
  final double left, top, width, height;

  /// Engine confidence 0..1, null when the engine doesn't report one
  /// (ML Kit Flutter per-line confidence is unconfirmed, see CLAUDE.md).
  final double? confidence;

  const OcrLine(this.text, {this.left = 0, this.top = 0, this.width = 0, this.height = 0, this.confidence});

  factory OcrLine.fromJson(Map<String, dynamic> j) => OcrLine(
    j['text'] as String,
    left: (j['left'] as num?)?.toDouble() ?? 0,
    top: (j['top'] as num?)?.toDouble() ?? 0,
    width: (j['width'] as num?)?.toDouble() ?? 0,
    height: (j['height'] as num?)?.toDouble() ?? 0,
    confidence: (j['confidence'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'text': text,
    'left': left,
    'top': top,
    'width': width,
    'height': height,
    if (confidence != null) 'confidence': confidence,
  };
}

class OcrPage {
  final List<OcrLine> lines;
  const OcrPage(this.lines);

  factory OcrPage.fromJson(Map<String, dynamic> j) =>
      OcrPage([for (final l in j['lines'] as List) OcrLine.fromJson(l as Map<String, dynamic>)]);

  Map<String, dynamic> toJson() => {
    'lines': [for (final l in lines) l.toJson()],
  };

  /// Convenience for tests: one line per string, heights given or uniform.
  factory OcrPage.fromText(List<String> lines, {List<double>? heights}) =>
      OcrPage([for (var i = 0; i < lines.length; i++) OcrLine(lines[i], top: i * 20.0, height: heights?[i] ?? 12)]);
}

abstract class OcrAdapter {
  Future<OcrPage> recognize(String imagePath);
}
