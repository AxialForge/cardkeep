import 'dart:async';
import 'dart:typed_data';

import 'package:card_organizer/core/sync/net/pairing.dart';
import 'package:card_organizer/core/sync/net/sync_client.dart';
import 'package:card_organizer/features/sync/webcam/webcam_scan.dart';
import 'package:card_organizer/features/sync/webcam/webcam_source.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../helpers/qr_pictures.dart';

/// A webcam that serves the stills it is given, in order, and writes down what was done to it.
class FakeWebcam implements WebcamSource {
  WebcamOpen result;
  @override
  String? detail;
  final List<Uint8List?> frames;
  final events = <String>[];
  int captures = 0;

  FakeWebcam({this.result = WebcamOpen.ready, this.detail, this.frames = const []});

  @override
  Future<WebcamOpen> open() async {
    events.add('open');
    return result;
  }

  @override
  Future<Uint8List?> captureFrame() async {
    events.add('capture');
    final i = captures++;
    // Past the script, the last picture (or none) keeps coming.
    if (frames.isEmpty) return null;
    return frames[i < frames.length ? i : frames.length - 1];
  }

  @override
  Widget buildPreview(BuildContext context) => const SizedBox();

  @override
  Future<void> close() async => events.add('close');
}

/// A picture whose "decoded text" is just the text in it, so the state machine can be tested alone.
Uint8List _pic(String text) => Uint8List.fromList(text.codeUnits);
Future<String?> _readPic(Uint8List b) async => b.isEmpty ? null : String.fromCharCodes(b);

WebcamScanController _controller(
  FakeWebcam cam, {
  PairCode? onCode,
  Future<String?> Function(Uint8List)? decode,
  Duration warningFor = const Duration(milliseconds: 150),
}) => WebcamScanController(
  source: cam,
  onCode: onCode ?? (_) async => null,
  decode: decode ?? _readPic,
  interval: const Duration(milliseconds: 10),
  warningFor: warningFor,
);

Future<void> _until(WebcamScanController c, WebcamScanPhase phase) async {
  for (var i = 0; i < 300; i++) {
    if (c.state.phase == phase) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for $phase; stuck at ${c.state.phase}');
}

void main() {
  final good = pairingTextForTests;

  group('opening the camera', () {
    test('no camera on the PC', () async {
      final cam = FakeWebcam(result: WebcamOpen.none);
      final c = _controller(cam);
      await c.start();
      expect(c.state.phase, WebcamScanPhase.noCamera);
      expect(c.state.canRetry, isFalse, reason: 'plugging one in needs a new start, offered as Paste instead too');
      expect(cam.captures, 0);
      c.dispose();
    });

    test('Windows camera privacy says no', () async {
      final c = _controller(FakeWebcam(result: WebcamOpen.denied));
      await c.start();
      expect(c.state.phase, WebcamScanPhase.denied);
      expect(c.state.canRetry, isTrue);
      c.dispose();
    });

    test('another app holds the camera, with the plugin text kept for the dialog', () async {
      final c = _controller(FakeWebcam(result: WebcamOpen.busy, detail: 'InitCamera failed.'));
      await c.start();
      expect(c.state.phase, WebcamScanPhase.busy);
      expect(c.state.message, 'InitCamera failed.');
      expect(c.state.canRetry, isTrue);
      c.dispose();
    });

    test('Try again opens the camera again and carries on', () async {
      final cam = FakeWebcam(result: WebcamOpen.busy, frames: [_pic(good)]);
      final c = _controller(cam);
      await c.start();
      expect(c.state.phase, WebcamScanPhase.busy);
      cam.result = WebcamOpen.ready;
      await c.start();
      await _until(c, WebcamScanPhase.done);
      expect(cam.events.where((e) => e == 'open'), hasLength(2));
      c.dispose();
    });
  });

  group('scanning', () {
    test('a good code: the camera is closed before pairing starts, then done', () async {
      final order = <String>[];
      final cam = FakeWebcam(frames: [null, _pic(''), _pic(good)]);
      final c = _controller(
        cam,
        onCode: (text) async {
          order.add('pair:${cam.events.last}');
          expect(text, good);
          return null;
        },
      );
      await c.start();
      expect(c.state.phase, WebcamScanPhase.scanning);
      await _until(c, WebcamScanPhase.done);
      expect(order, ['pair:close'], reason: 'closed the moment a good code was read');
      expect(cam.events.last, 'close');
      final capturesAtDone = cam.captures;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(cam.captures, capturesAtDone, reason: 'no more pictures after the scan');
      c.dispose();
    });

    test('a QR that is not CardKeep: warns, keeps looking, then pairs with the real one', () async {
      final cam = FakeWebcam(frames: [_pic('https://example.com/menu'), _pic('https://example.com/menu'), _pic(good)]);
      final c = _controller(cam);
      await c.start();
      await _until(c, WebcamScanPhase.notCardKeep);
      expect(c.state.cameraOn, isTrue, reason: 'still looking');
      await _until(c, WebcamScanPhase.done);
      c.dispose();
    });

    test('the warning goes away when that QR is no longer in view', () async {
      final cam = FakeWebcam(frames: [_pic('https://example.com/menu'), _pic('')]);
      final c = _controller(cam);
      await c.start();
      await _until(c, WebcamScanPhase.notCardKeep);
      await _until(c, WebcamScanPhase.scanning);
      c.dispose();
    });

    test('a code from a newer CardKeep is explained, and scanning goes on', () async {
      final newer = PairingPayload(
        host: '192.168.1.5',
        port: 1234,
        token: 'tok',
        certSha256: 'b' * 64,
        deviceName: 'Phone',
        version: 99,
      ).toQrText();
      final cam = FakeWebcam(frames: [_pic(newer)]);
      final c = _controller(cam);
      await c.start();
      await _until(c, WebcamScanPhase.newerVersion);
      expect(c.state.message, contains('newer'));
      expect(c.state.cameraOn, isTrue);
      c.dispose();
    });

    test('a damaged code with the CardKeep prefix is flagged, not paired', () async {
      var paired = false;
      final cam = FakeWebcam(frames: [_pic('cardkeep-sync:!!!notbase64!!!')]);
      final c = _controller(
        cam,
        onCode: (_) async {
          paired = true;
          return null;
        },
      );
      await c.start();
      await _until(c, WebcamScanPhase.notCardKeep);
      expect(paired, isFalse);
      c.dispose();
    });
  });

  group('when pairing does not work', () {
    test('an expired or used code: camera closed, a clear state, and scanning again can succeed', () async {
      var tries = 0;
      final cam = FakeWebcam(frames: [_pic(good)]);
      final c = _controller(
        cam,
        onCode: (_) async {
          tries++;
          return tries == 1
              ? const SyncException('bad_token', 'That pairing code has expired or was already used.')
              : null;
        },
      );
      await c.start();
      await _until(c, WebcamScanPhase.expired);
      expect(c.state.message, contains('expired'));
      expect(c.state.canRetry, isTrue);
      expect(cam.events.last, 'close');
      await c.start();
      await _until(c, WebcamScanPhase.done);
      expect(tries, 2);
      c.dispose();
    });

    test('any other pairing error shows its message', () async {
      final cam = FakeWebcam(frames: [_pic(good)]);
      final c = _controller(cam, onCode: (_) async => const SyncException('unreachable', 'Could not reach the phone.'));
      await c.start();
      await _until(c, WebcamScanPhase.failed);
      expect(c.state.message, 'Could not reach the phone.');
      expect(c.state.canRetry, isTrue);
      c.dispose();
    });
  });

  group('letting go of the camera', () {
    test('closing the dialog while scanning closes the camera and stops taking pictures', () async {
      final cam = FakeWebcam(frames: [_pic('')]);
      final c = _controller(cam);
      await c.start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(cam.captures, greaterThan(0));
      c.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cam.events, contains('close'));
      final n = cam.captures;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(cam.captures, n);
    });

    test('closing while the camera is still starting closes it too', () async {
      final slow = _SlowOpen();
      final c = _controller(slow);
      final started = c.start();
      c.dispose();
      slow.release.complete();
      await started;
      expect(slow.events, contains('close'));
      expect(slow.captures, 0);
    });

    test('starting twice does not run two scan loops', () async {
      final cam = FakeWebcam(frames: [_pic('')]);
      final c = _controller(cam);
      await c.start();
      await c.start();
      final before = cam.captures;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final perSecond = (cam.captures - before) / 0.2;
      expect(perSecond, lessThan(120), reason: 'one loop at a 10 ms pause is under about 100 a second');
      c.dispose();
    });
  });

  group('with the real decoder', () {
    test('a picture of the phone\'s real pairing code pairs', () async {
      final frame = webcamFrame(qrImage(good), w: 1280, h: 720, size: 0.4);
      final cam = FakeWebcam(
        frames: [
          Uint8List.fromList(img.encodeJpg(img.Image(width: 640, height: 480))),
          Uint8List.fromList(img.encodeJpg(frame, quality: 85)),
        ],
      );
      String? got;
      final c = WebcamScanController(
        source: cam,
        onCode: (t) async {
          got = t;
          return null;
        },
        interval: const Duration(milliseconds: 10),
      );
      await c.start();
      await _until(c, WebcamScanPhase.done);
      expect(got, good);
      expect(PairingPayload.parse(got!).host, '192.168.1.65');
      c.dispose();
    });
  });
}

/// A camera that takes its time to open.
class _SlowOpen extends FakeWebcam {
  final release = Completer<void>();
  @override
  Future<WebcamOpen> open() async {
    events.add('open');
    await release.future;
    return WebcamOpen.ready;
  }
}
