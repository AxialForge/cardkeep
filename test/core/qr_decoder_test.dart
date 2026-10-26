import 'dart:typed_data';

import 'package:card_organizer/core/qr/qr_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

import '../helpers/qr_pictures.dart';

void main() {
  test('the real pairing code is a dense, version-10+ QR (the case to beat)', () {
    final qr = QrCode.fromData(data: pairingTextForTests, errorCorrectLevel: QrErrorCorrectLevel.L);
    expect(qr.typeNumber, greaterThanOrEqualTo(8));
  });

  group('clean pictures', () {
    for (final px in [3, 4, 6, 10]) {
      test('$px px per module straight on', () {
        expect(QrDecoder.decodeImage(qrImage(pairingTextForTests, px: px)), pairingTextForTests);
      });
    }

    test('from encoded jpeg and png bytes', () {
      final image = webcamFrame(qrImage(pairingTextForTests), size: 0.5);
      expect(QrDecoder.decodeBytes(Uint8List.fromList(img.encodePng(image))), pairingTextForTests);
      expect(QrDecoder.decodeBytes(Uint8List.fromList(img.encodeJpg(image, quality: 80))), pairingTextForTests);
    });

    test('no code, a blank picture and garbage bytes give null', () {
      expect(QrDecoder.decodeImage(img.Image(width: 640, height: 480)), isNull);
      expect(QrDecoder.decodeBytes(Uint8List.fromList([1, 2, 3, 4])), isNull);
      final photo = img.Image(width: 640, height: 480);
      addNoise(photo, 60, 1);
      expect(QrDecoder.decodeImage(photo), isNull);
    });

    test('a code that is not CardKeep text still decodes (the caller decides)', () {
      expect(QrDecoder.decodeImage(qrImage('https://example.com/menu', px: 8)), 'https://example.com/menu');
    });
  });

  group('webcam-like pictures', () {
    test('the code fills a third of a 720p frame', () {
      expect(QrDecoder.decodeImage(webcamFrame(qrImage(pairingTextForTests), size: 0.33)), pairingTextForTests);
    });

    test('the code fills half of a 1080p frame', () {
      expect(
        QrDecoder.decodeImage(webcamFrame(qrImage(pairingTextForTests), w: 1920, h: 1080, size: 0.35)),
        pairingTextForTests,
      );
    });

    test('white on black (dark mode screen)', () {
      final inv = qrImage(pairingTextForTests, px: 6);
      for (final p in inv) {
        p
          ..r = 255 - p.r
          ..g = 255 - p.g
          ..b = 255 - p.b;
      }
      expect(QrDecoder.decodeImage(webcamFrame(inv, size: 0.4, bg: 220)), pairingTextForTests);
    });

    test('with sensor noise', () {
      final f = webcamFrame(qrImage(pairingTextForTests), size: 0.4);
      addNoise(f, 28, 7);
      expect(QrDecoder.decodeImage(f), pairingTextForTests);
    });

    test('with a patch of glare over a corner of the screen', () {
      final f = webcamFrame(qrImage(pairingTextForTests), size: 0.4);
      addGlare(f);
      expect(QrDecoder.decodeImage(f), pairingTextForTests);
    });

    test('slightly turned (a phone held at an angle)', () {
      for (final angle in [-12.0, 8.0, 20.0]) {
        expect(
          QrDecoder.decodeImage(webcamFrame(qrImage(pairingTextForTests), size: 0.4, angle: angle)),
          pairingTextForTests,
          reason: 'angle $angle',
        );
      }
    });

    test('out of focus (blurred)', () {
      final f = webcamFrame(qrImage(pairingTextForTests), size: 0.4);
      final blurred = img.gaussianBlur(f, radius: 2);
      expect(QrDecoder.decodeImage(blurred), pairingTextForTests);
    });

    test('dim picture (low contrast)', () {
      final f = webcamFrame(qrImage(pairingTextForTests), size: 0.4);
      for (final p in f) {
        p
          ..r = 70 + p.r * 0.3
          ..g = 70 + p.g * 0.3
          ..b = 70 + p.b * 0.3;
      }
      expect(QrDecoder.decodeImage(f), pairingTextForTests);
    });

    test('a small code: a fifth of a 1080p frame', () {
      expect(
        QrDecoder.decodeImage(webcamFrame(qrImage(pairingTextForTests), w: 1920, h: 1080, size: 0.22)),
        pairingTextForTests,
      );
    });

    // Past about 7% the dense code can no longer be read: the dialog tells people to face the phone to the camera.
    test('tilted back a little (top edge up to 5% narrower)', () {
      for (final squeeze in [0.03, 0.05]) {
        final f = webcamFrame(qrImage(pairingTextForTests), w: 1920, h: 1080, size: 0.4);
        expect(QrDecoder.decodeImage(tiltBack(f, squeeze)), pairingTextForTests, reason: 'squeeze $squeeze');
      }
    });

    test('noisy and a little blurred and tilted', () {
      for (final squeeze in [0.0, 0.03, 0.05]) {
        final f = tiltBack(webcamFrame(qrImage(pairingTextForTests), w: 1920, h: 1080, size: 0.4), squeeze);
        addNoise(f, 20, 3);
        expect(QrDecoder.decodeImage(img.gaussianBlur(f, radius: 1)), pairingTextForTests, reason: 'squeeze $squeeze');
      }
    });

    test('screen moire: fine stripes over the code', () {
      final f = webcamFrame(qrImage(pairingTextForTests), size: 0.45);
      for (final p in f) {
        if (p.y % 3 == 0) {
          p
            ..r = p.r * 0.85
            ..g = p.g * 0.85
            ..b = p.b * 0.85;
        }
      }
      expect(QrDecoder.decodeImage(f), pairingTextForTests);
    });
  });

  test('works on a background isolate', () async {
    final bytes = Uint8List.fromList(img.encodeJpg(webcamFrame(qrImage(pairingTextForTests), size: 0.45), quality: 85));
    expect(await QrDecoder.decodeBytesInIsolate(bytes), pairingTextForTests);
  });

  test('a 1080p frame is read in a reasonable time', () {
    final f = webcamFrame(qrImage(pairingTextForTests), w: 1920, h: 1080, size: 0.35);
    final sw = Stopwatch()..start();
    expect(QrDecoder.decodeImage(f), pairingTextForTests);
    expect(sw.elapsedMilliseconds, lessThan(4000));
  });
}
