import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'qr_decoder.dart';

/// What one webcam picture held: the text of a QR code if there was one, and how
/// sharp the picture was (higher is sharper; -1 when it could not be measured).
class FrameReading {
  final String? text;
  final double sharpness;
  const FrameReading(this.text, this.sharpness);
}

/// Reads a webcam still for the pairing scan (S16.12): looks for a QR code and,
/// only when there is none, measures how sharp the picture is, so the dialog can
/// say "looks blurry" while the person is holding the phone out of focus.
class FrameReader {
  FrameReader._();

  /// Below this a picture that holds no code counts as blurry. Measured on a QR
  /// code on a dark desk (320 px wide): sharp pictures read 40000 to 70000, a code
  /// out of focus enough to stop a decoder reads under 10000 (see the test).
  static const blurryBelow = 8000.0;

  /// The picture is looked at this wide: enough to see focus, cheap to measure.
  static const _width = 320;
  static const _block = 32;

  static FrameReading read(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) return const FrameReading(null, -1);
    final text = QrDecoder.decodeImage(image);
    if (text != null) return FrameReading(text, -1);
    return FrameReading(null, sharpnessOf(image));
  }

  /// [read] on a background isolate, so the preview never stutters.
  static Future<FrameReading> readInIsolate(Uint8List bytes) => Isolate.run(() => read(bytes));

  /// Focus measure: how strong the edges are in the most detailed parts of the
  /// picture. A phone held out of focus loses its hard black-and-white edges, so
  /// the variance of the Laplacian in the busiest blocks drops. The busiest few
  /// blocks are used, not the whole frame, because most of a webcam picture is
  /// plain wall or desk even when the phone in it is sharp.
  static double sharpnessOf(img.Image source) {
    final small = source.width > _width
        ? img.copyResize(source, width: _width, interpolation: img.Interpolation.average)
        : source;
    final w = small.width, h = small.height;
    if (w < _block * 2 || h < _block * 2) return 0;
    final lum = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = small.getPixel(x, y);
        lum[y * w + x] = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).toDouble();
      }
    }
    final blocksX = w ~/ _block, blocksY = h ~/ _block;
    final variances = <double>[];
    for (var by = 0; by < blocksY; by++) {
      for (var bx = 0; bx < blocksX; bx++) {
        var sum = 0.0, sumSq = 0.0, n = 0;
        for (var y = math.max(1, by * _block); y < math.min(h - 1, (by + 1) * _block); y++) {
          for (var x = math.max(1, bx * _block); x < math.min(w - 1, (bx + 1) * _block); x++) {
            final i = y * w + x;
            final lap = 4 * lum[i] - lum[i - 1] - lum[i + 1] - lum[i - w] - lum[i + w];
            sum += lap;
            sumSq += lap * lap;
            n++;
          }
        }
        if (n > 0) {
          final mean = sum / n;
          variances.add(sumSq / n - mean * mean);
        }
      }
    }
    if (variances.isEmpty) return 0;
    variances.sort((a, b) => b.compareTo(a));
    final top = math.max(1, (variances.length * 0.06).ceil());
    var total = 0.0;
    for (var i = 0; i < top; i++) {
      total += variances[i];
    }
    return total / top;
  }
}
