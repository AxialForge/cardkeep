import 'dart:math' as math;

import 'package:card_organizer/core/sync/net/pairing.dart';
import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

/// The real thing the phone shows: a pairing code, drawn the way qr_flutter does
/// (error correction L, smallest version that fits, white square around it).
final pairingPayloadForTests = PairingPayload(
  host: '192.168.1.65',
  port: 40263,
  token: 'q3J7mP0xV2nL8cT5yH1aKw',
  certSha256: 'a' * 64,
  deviceName: 'CardKeep on this phone',
);
final pairingTextForTests = pairingPayloadForTests.toQrText();

/// The code as a picture with [px] pixels per module on a white square.
img.Image qrImage(String text, {int px = 6, int quiet = 4, int level = QrErrorCorrectLevel.L}) {
  final qr = QrImage(QrCode.fromData(data: text, errorCorrectLevel: level));
  final n = qr.moduleCount + 2 * quiet;
  final image = img.Image(width: n * px, height: n * px);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  for (var y = 0; y < qr.moduleCount; y++) {
    for (var x = 0; x < qr.moduleCount; x++) {
      if (!qr.isDark(y, x)) continue;
      img.fillRect(
        image,
        x1: (x + quiet) * px,
        y1: (y + quiet) * px,
        x2: (x + quiet + 1) * px - 1,
        y2: (y + quiet + 1) * px - 1,
        color: img.ColorRgb8(0, 0, 0),
      );
    }
  }
  return image;
}

/// A webcam frame: the code at [size] of the frame width on a dark desk.
img.Image webcamFrame(img.Image code, {int w = 1280, int h = 720, double size = 0.35, double angle = 0, int bg = 40}) {
  final frame = img.Image(width: w, height: h);
  img.fill(frame, color: img.ColorRgb8(bg, bg, bg + 6));
  var c = img.copyResize(code, width: (w * size).round(), interpolation: img.Interpolation.average);
  if (angle != 0) c = img.copyRotate(c, angle: angle, interpolation: img.Interpolation.linear);
  img.compositeImage(frame, c, dstX: (w - c.width) ~/ 2, dstY: (h - c.height) ~/ 2);
  return frame;
}

void addNoise(img.Image image, int amount, int seed) {
  final r = math.Random(seed);
  for (final p in image) {
    final d = r.nextInt(amount * 2 + 1) - amount;
    p
      ..r = (p.r + d).clamp(0, 255)
      ..g = (p.g + d).clamp(0, 255)
      ..b = (p.b + d).clamp(0, 255);
  }
}

/// A bright patch of screen glare across one corner.
void addGlare(img.Image image) {
  final cx = image.width * 0.7, cy = image.height * 0.3, rad = image.width * 0.18;
  for (final p in image) {
    final d = math.sqrt(math.pow(p.x - cx, 2) + math.pow(p.y - cy, 2));
    if (d < rad) {
      final k = 1 - d / rad;
      p
        ..r = (p.r + 150 * k).clamp(0, 255)
        ..g = (p.g + 150 * k).clamp(0, 255)
        ..b = (p.b + 150 * k).clamp(0, 255);
    }
  }
}

/// A mild perspective: the top edge is [squeeze] narrower than the bottom, as when
/// a phone is tilted back from the camera.
img.Image tiltBack(img.Image src, double squeeze) {
  final out = img.Image(width: src.width, height: src.height);
  img.fill(out, color: img.ColorRgb8(40, 40, 46));
  for (var y = 0; y < out.height; y++) {
    final t = y / out.height; // 0 top, 1 bottom
    final scale = 1 - squeeze * (1 - t);
    for (var x = 0; x < out.width; x++) {
      final sx = ((x - out.width / 2) / scale + out.width / 2);
      if (sx < 0 || sx >= src.width - 1) continue;
      final p = src.getPixelInterpolate(sx, y.toDouble());
      out.setPixel(x, y, p);
    }
  }
  return out;
}
