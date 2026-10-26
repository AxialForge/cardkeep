import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Reads a QR code out of a photo (S16.12): the pairing code on the phone's
/// screen seen by a PC webcam, or any picture with a QR in it. Pure Dart, so it
/// runs in a background isolate and in tests.
///
/// A webcam sees a phone screen at a slant, with glare, moire and a QR that fills
/// only part of the frame. So it tries a short list of ways to look: the whole
/// frame and the middle of it, a few sizes, the picture as it is and with the
/// contrast stretched, both black-on-white and white-on-black, and two ways of
/// deciding which pixels are dark. The cheap and likely ones come first.
class QrDecoder {
  QrDecoder._();

  /// The longest side a picture is looked at before trying smaller sizes.
  static const maxSide = 1600;

  /// The text of the first QR code found, or null when there is none.
  static String? decodeImage(img.Image source) {
    final gray = _Gray.from(source);
    // Whole frame first (most phone screens are held up large), then the middle,
    // where someone holding a code up to a camera usually puts it.
    for (final view in _views(gray)) {
      for (final stretch in const [false, true]) {
        final g = stretch ? view.stretched() : view;
        for (final invert in const [false, true]) {
          for (final hybrid in const [true, false]) {
            final text = _try(g, invert: invert, hybrid: hybrid);
            if (text != null) return text;
          }
        }
      }
    }
    return null;
  }

  /// The text of a QR code in encoded picture [bytes] (jpeg, png, ...), or null.
  static String? decodeBytes(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    return decodeImage(image);
  }

  /// [decodeBytes] on a background isolate, so the preview never stutters.
  static Future<String?> decodeBytesInIsolate(Uint8List bytes) => Isolate.run(() => decodeBytes(bytes));

  /// Sizes and crops to look at, most likely first.
  static Iterable<_Gray> _views(_Gray full) sync* {
    final big = full.fit(maxSide);
    yield big;
    // A smaller copy averages away screen moire and sensor noise.
    final long = math.max(big.width, big.height);
    if (long > 900) yield big.fit(900);
    // The middle 70% at full size: a code held up to the camera, looked at more closely.
    yield big.crop(0.15, 0.15, 0.70, 0.70);
    if (long > 560) yield big.fit(560);
    yield big.crop(0.25, 0.1, 0.5, 0.8);
    if (long > 360) yield big.fit(360);
  }

  static String? _try(_Gray g, {required bool invert, required bool hybrid}) {
    try {
      final pixels = g.packed();
      LuminanceSource source = RGBLuminanceSource(g.width, g.height, pixels);
      if (invert) source = InvertedLuminanceSource(source);
      final bitmap = BinaryBitmap(hybrid ? HybridBinarizer(source) : GlobalHistogramBinarizer(source));
      final hints = DecodeHints()..put(DecodeHintType.tryHarder);
      return QRCodeReader().decode(bitmap, hints: hints).text;
    } on ReaderException {
      return null;
    } on ArgumentError {
      return null; // includes RangeError
    }
  }
}

/// An 8-bit grey picture with the few operations the decoder needs.
class _Gray {
  final int width;
  final int height;
  final Uint8List data;
  const _Gray(this.width, this.height, this.data);

  factory _Gray.from(img.Image image) {
    final rgba = image.convert(numChannels: 4);
    final w = rgba.width, h = rgba.height;
    final out = Uint8List(w * h);
    var i = 0;
    for (final p in rgba) {
      // Green-leaning average, like zxing's own.
      out[i++] = ((p.r.toInt() + 2 * p.g.toInt() + p.b.toInt()) >> 2);
    }
    return _Gray(w, h, out);
  }

  /// This picture shrunk so its longest side is at most [side] (area average).
  _Gray fit(int side) {
    final long = math.max(width, height);
    if (long <= side) return this;
    final scale = side / long;
    final nw = math.max(1, (width * scale).round());
    final nh = math.max(1, (height * scale).round());
    final out = Uint8List(nw * nh);
    for (var y = 0; y < nh; y++) {
      final y0 = (y * height) ~/ nh;
      final y1 = math.max(y0 + 1, ((y + 1) * height) ~/ nh);
      for (var x = 0; x < nw; x++) {
        final x0 = (x * width) ~/ nw;
        final x1 = math.max(x0 + 1, ((x + 1) * width) ~/ nw);
        var sum = 0;
        for (var yy = y0; yy < y1; yy++) {
          final row = yy * width;
          for (var xx = x0; xx < x1; xx++) {
            sum += data[row + xx];
          }
        }
        out[y * nw + x] = sum ~/ ((y1 - y0) * (x1 - x0));
      }
    }
    return _Gray(nw, nh, out);
  }

  /// The part of this picture at fractions [fx], [fy], [fw], [fh] of its size.
  _Gray crop(double fx, double fy, double fw, double fh) {
    final x = (width * fx).round();
    final y = (height * fy).round();
    final w = math.min(width - x, (width * fw).round());
    final h = math.min(height - y, (height * fh).round());
    final out = Uint8List(w * h);
    for (var row = 0; row < h; row++) {
      out.setRange(row * w, row * w + w, data, (y + row) * width + x);
    }
    return _Gray(w, h, out);
  }

  /// Contrast stretched between the 2nd and 98th percentile of the greys, which
  /// lifts a washed-out screen or a dim room.
  _Gray stretched() {
    final hist = List<int>.filled(256, 0);
    for (final v in data) {
      hist[v]++;
    }
    final total = data.length;
    var lo = 0, hi = 255, acc = 0;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= total * 0.02) {
        lo = v;
        break;
      }
    }
    acc = 0;
    for (var v = 255; v >= 0; v--) {
      acc += hist[v];
      if (acc >= total * 0.02) {
        hi = v;
        break;
      }
    }
    if (hi - lo < 16) return this;
    final out = Uint8List(data.length);
    final k = 255.0 / (hi - lo);
    for (var i = 0; i < data.length; i++) {
      out[i] = ((data[i] - lo) * k).round().clamp(0, 255);
    }
    return _Gray(width, height, out);
  }

  /// One grey per pixel packed as grey,grey,grey so zxing's luminance is that grey.
  Int32List packed() {
    final out = Int32List(data.length);
    for (var i = 0; i < data.length; i++) {
      final g = data[i];
      out[i] = (0xFF << 24) | (g << 16) | (g << 8) | g;
    }
    return out;
  }
}
