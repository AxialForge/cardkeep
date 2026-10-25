import 'dart:convert';
import 'dart:ui';

/// The Windows window's place and size, kept between runs (S16.11).
class WindowBounds {
  final double left, top, width, height;
  final bool maximized;
  const WindowBounds(this.left, this.top, this.width, this.height, {this.maximized = false});

  static const defaultSize = Size(1180, 780);
  static const minSize = Size(560, 640);

  Rect get rect => Rect.fromLTWH(left, top, width, height);

  String encode() => jsonEncode({'l': left, 't': top, 'w': width, 'h': height, 'max': maximized});

  /// Reads what [encode] wrote; null for anything damaged or too small to use.
  static WindowBounds? decode(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final j = (jsonDecode(text) as Map).cast<String, Object?>();
      final b = WindowBounds(
        (j['l'] as num).toDouble(),
        (j['t'] as num).toDouble(),
        (j['w'] as num).toDouble(),
        (j['h'] as num).toDouble(),
        maximized: j['max'] == true,
      );
      if (b.width < minSize.width || b.height < minSize.height) return null;
      return b;
    } catch (_) {
      return null;
    }
  }

  /// Keeps the window on a screen: if it would sit outside every display in
  /// [screens] (a monitor was unplugged), it moves to the first screen's corner.
  WindowBounds onScreen(List<Rect> screens) {
    if (screens.isEmpty) return this;
    final visible = screens.any((s) {
      final overlap = s.intersect(rect);
      return overlap.width >= 120 && overlap.height >= 80;
    });
    if (visible) return this;
    final s = screens.first;
    final w = width.clamp(minSize.width, s.width).toDouble();
    final h = height.clamp(minSize.height, s.height).toDouble();
    return WindowBounds(s.left + 40, s.top + 40, w, h, maximized: maximized);
  }
}
