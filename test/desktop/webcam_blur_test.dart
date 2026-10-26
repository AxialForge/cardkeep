import 'dart:typed_data';

import 'package:card_organizer/app/theme.dart';
import 'package:card_organizer/core/qr/frame_reader.dart';
import 'package:card_organizer/features/sync/webcam/webcam_qr_dialog.dart';
import 'package:card_organizer/features/sync/webcam/webcam_scan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../helpers/qr_pictures.dart';
import 'webcam_scan_test.dart' show FakeWebcam;

Uint8List _png(img.Image i) => Uint8List.fromList(img.encodePng(i));

void main() {
  group('sharpness measure', () {
    final code = qrImage(pairingTextForTests, px: 6);

    test('a sharp frame reads well above the blurry line, a blurred one below it', () {
      final sharp = FrameReader.sharpnessOf(webcamFrame(code));
      final soft = FrameReader.sharpnessOf(img.gaussianBlur(webcamFrame(code), radius: 6));
      expect(sharp, greaterThan(FrameReader.blurryBelow * 2));
      expect(soft, lessThan(FrameReader.blurryBelow));
      expect(sharp, greaterThan(soft * 3));
    });

    test('sharpness falls steadily as the picture goes out of focus', () {
      final values = [
        for (final r in [0, 1, 2, 4, 8])
          FrameReader.sharpnessOf(r == 0 ? webcamFrame(code) : img.gaussianBlur(webcamFrame(code), radius: r)),
      ];
      for (var i = 1; i < values.length; i++) {
        expect(values[i], lessThan(values[i - 1]));
      }
    });

    test('a small sharp code on a big empty desk still reads as sharp', () {
      expect(FrameReader.sharpnessOf(webcamFrame(code, size: 0.2)), greaterThan(FrameReader.blurryBelow));
    });

    test('a blank picture and a tiny one read as zero', () {
      expect(FrameReader.sharpnessOf(img.Image(width: 1280, height: 720)), 0);
      expect(FrameReader.sharpnessOf(img.Image(width: 20, height: 20)), 0);
    });

    test('a frame with a code gives its text; one without gives its sharpness', () {
      final withCode = FrameReader.read(_png(webcamFrame(code, size: 0.5)));
      expect(withCode.text, pairingTextForTests);
      final without = FrameReader.read(_png(img.gaussianBlur(webcamFrame(code), radius: 8)));
      expect(without.text, isNull);
      expect(without.sharpness, greaterThanOrEqualTo(0));
      expect(without.sharpness, lessThan(FrameReader.blurryBelow));
    });

    test('bytes that are not a picture give no text and unknown sharpness', () {
      final r = FrameReader.read(Uint8List.fromList([1, 2, 3]));
      expect(r.text, isNull);
      expect(r.sharpness, -1);
    });
  });

  group('the blurry hint', () {
    final frame = Uint8List.fromList([1]);

    WebcamScanController controllerFor(List<double> sharpness, {String? codeAt, int blurryFrames = 3}) {
      var i = 0;
      return WebcamScanController(
        source: FakeWebcam(frames: [frame]),
        onCode: (_) async => null,
        read: (_) async {
          final s = sharpness[i < sharpness.length ? i : sharpness.length - 1];
          final n = i++;
          return FrameReading(codeAt != null && n == sharpness.length ? codeAt : null, s);
        },
        interval: const Duration(milliseconds: 5),
        blurryFrames: blurryFrames,
        blurryBelow: 100,
      );
    }

    Future<void> until(WebcamScanController c, bool Function() ok) async {
      for (var i = 0; i < 300 && !ok(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(ok(), isTrue);
    }

    test('three blurry pictures in a row with no code say so', () async {
      final c = controllerFor([10, 10, 10, 10]);
      addTearDown(c.dispose);
      await c.start();
      await until(c, () => c.state.looksBlurry);
      expect(c.state.phase, WebcamScanPhase.scanning);
    });

    test('two blurry pictures are not enough', () async {
      final c = controllerFor([10, 10, 500, 500]);
      addTearDown(c.dispose);
      await c.start();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(c.state.looksBlurry, isFalse);
    });

    test('a sharp picture takes the hint away again', () async {
      final c = controllerFor([10, 10, 10, 10, 10, 5000]);
      addTearDown(c.dispose);
      await c.start();
      await until(c, () => c.state.looksBlurry);
      await until(c, () => !c.state.looksBlurry);
    });

    test('pictures whose sharpness is unknown never say blurry', () async {
      final c = controllerFor([-1, -1, -1, -1, -1]);
      addTearDown(c.dispose);
      await c.start();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(c.state.looksBlurry, isFalse);
    });

    test('the hint starts over when the camera is started again', () async {
      final c = controllerFor([10, 10, 10, 10]);
      addTearDown(c.dispose);
      await c.start();
      await until(c, () => c.state.looksBlurry);
      final again = c.start();
      expect(c.state.looksBlurry, isFalse);
      await again;
    });
  });

  group('the dialog', () {
    Future<void> show(WidgetTester tester, WebcamScanController c) async {
      await tester.pumpWidget(MaterialApp(theme: ThemeData(), home: Scaffold(body: WebcamQrDialog(controller: c))));
    }

    testWidgets('tells you the distance and shows the blurry hint only while it looks blurry', (tester) async {
      AppPalette.current = AppPalette.light;
      var sharp = false;
      final c = WebcamScanController(
        source: FakeWebcam(frames: [Uint8List.fromList([1])]),
        onCode: (_) async => null,
        read: (_) async => FrameReading(null, sharp ? 9000 : 10),
        interval: const Duration(milliseconds: 20),
        blurryFrames: 2,
        blurryBelow: 100,
      );
      await show(tester, c);
      expect(find.textContaining('40 to 60 cm'), findsOneWidget);
      expect(find.byKey(const Key('webcam-blurry')), findsNothing);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(find.byKey(const Key('webcam-blurry')), findsOneWidget);
      expect(find.textContaining('Looks blurry'), findsOneWidget);
      sharp = true;
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(find.byKey(const Key('webcam-blurry')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100)); // the last wait between pictures ends
    });
  });
}
