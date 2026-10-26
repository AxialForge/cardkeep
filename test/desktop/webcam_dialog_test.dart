import 'package:card_organizer/core/platform/platform_info.dart';
import 'package:card_organizer/core/sync/net/sync_client.dart';
import 'package:card_organizer/features/sync/desktop_sync.dart';
import 'package:card_organizer/features/sync/desktop_sync_screen.dart';
import 'package:card_organizer/features/sync/sync_providers.dart';
import 'package:card_organizer/features/sync/webcam/webcam_qr_dialog.dart';
import 'package:card_organizer/features/sync/webcam/webcam_scan.dart';
import 'package:card_organizer/features/sync/webcam/webcam_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qr_pictures.dart';
import 'webcam_scan_test.dart' show FakeWebcam;

Uint8List _pic(String text) => Uint8List.fromList(text.codeUnits);
Future<String?> _read(Uint8List b) async => b.isEmpty ? null : String.fromCharCodes(b);

/// A button that opens the dialog and remembers how it ended.
class _Harness extends StatefulWidget {
  final FakeWebcam cam;
  final PairCode onCode;
  final Future<void> Function()? openCameraSettings;
  const _Harness({required this.cam, required this.onCode, this.openCameraSettings});
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  WebcamQrOutcome? outcome;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        children: [
          ElevatedButton(
            onPressed: () async {
              final o = await showWebcamQrDialog(
                context,
                source: widget.cam,
                onCode: widget.onCode,
                decode: _read,
                openCameraSettings: widget.openCameraSettings,
              );
              setState(() => outcome = o);
            },
            child: const Text('Open'),
          ),
          Text('outcome: ${outcome?.name}'),
        ],
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester, FakeWebcam cam, {PairCode? onCode, Future<void> Function()? settings}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: _Harness(cam: cam, onCode: onCode ?? (_) async => null, openCameraSettings: settings),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Takes the dialog away and lets the scan loop's last timer fire.
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 600));
}

String _status(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('webcam-status'))).data!;

void main() {
  group('the webcam dialog', () {
    testWidgets('while looking: instruction, status, Paste instead and Cancel', (tester) async {
      final cam = FakeWebcam(frames: [_pic('')]);
      await _open(tester, cam);
      expect(find.text('Scan the code on your phone'), findsOneWidget);
      expect(find.textContaining("On the phone open Sync to desktop"), findsOneWidget);
      expect(_status(tester), 'Looking for the code…');
      expect(find.text('Paste instead'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('outcome: cancelled'), findsOneWidget);
      expect(cam.events, contains('close'), reason: 'the camera is let go when the dialog closes');
      await _settle(tester);
    });

    testWidgets('no camera: says so and offers Paste instead', (tester) async {
      final cam = FakeWebcam(result: WebcamOpen.none);
      await _open(tester, cam);
      expect(_status(tester), startsWith('No camera found on this PC.'));
      expect(find.text('Try again'), findsNothing);
      await tester.tap(find.text('Paste instead'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('outcome: paste'), findsOneWidget);
      await _settle(tester);
    });

    testWidgets('Windows camera privacy: explains, opens the settings, and can try again', (tester) async {
      var opened = 0;
      final cam = FakeWebcam(result: WebcamOpen.denied);
      await _open(tester, cam, settings: () async => opened++);
      expect(_status(tester), contains('Windows is not letting CardKeep use the camera'));
      await tester.tap(find.text('Open camera settings'));
      expect(opened, 1);
      expect(find.text('Try again'), findsOneWidget);
      cam.result = WebcamOpen.ready;
      await tester.tap(find.text('Try again'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_status(tester), 'Looking for the code…');
      await _settle(tester);
    });

    testWidgets('camera busy: names the usual culprits and shows the plugin text', (tester) async {
      await _open(tester, FakeWebcam(result: WebcamOpen.busy, detail: 'InitCamera failed.'));
      expect(_status(tester), contains('Teams, Zoom, the Camera app'));
      expect(find.text('InitCamera failed.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      await _settle(tester);
    });

    testWidgets('a QR that is not CardKeep: a warning, and it keeps looking', (tester) async {
      await _open(tester, FakeWebcam(frames: [_pic('https://example.com/menu')]));
      await tester.pump(const Duration(milliseconds: 60));
      expect(_status(tester), contains('not a CardKeep pairing code'));
      expect(find.text('Cancel'), findsOneWidget);
      await _settle(tester);
    });

    testWidgets('a good code pairs and closes the dialog with "paired"', (tester) async {
      String? got;
      final cam = FakeWebcam(frames: [_pic(pairingTextForTests)]);
      await _open(
        tester,
        cam,
        onCode: (t) async {
          got = t;
          return null;
        },
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(got, pairingTextForTests);
      expect(find.text('outcome: paired'), findsOneWidget);
      expect(cam.events.last, 'close');
      await _settle(tester);
    });

    testWidgets('an expired code: tells what to do on the phone, and offers to scan the new one', (tester) async {
      final cam = FakeWebcam(frames: [_pic(pairingTextForTests)]);
      await _open(
        tester,
        cam,
        onCode: (_) async => const SyncException('bad_token', 'That pairing code has expired or was already used.'),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(_status(tester), contains('On the phone tap New code'));
      expect(find.text('Scan the new code'), findsOneWidget);
      expect(find.text('Paste instead'), findsOneWidget);
      await _settle(tester);
    });

    testWidgets('other pairing errors show their own message', (tester) async {
      final cam = FakeWebcam(frames: [_pic(pairingTextForTests)]);
      await _open(
        tester,
        cam,
        onCode: (_) async => const SyncException('unreachable', 'Could not reach the phone. Check the Wi-Fi.'),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(_status(tester), 'Could not reach the phone. Check the Wi-Fi.');
      await _settle(tester);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('fits a small window at ${scale * 100}% text in every state', (tester) async {
        tester.view.physicalSize = const Size(520, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        for (final cam in [
          FakeWebcam(result: WebcamOpen.none),
          FakeWebcam(result: WebcamOpen.denied),
          FakeWebcam(result: WebcamOpen.busy, detail: 'InitCamera failed with a long explanation from the plugin.'),
          FakeWebcam(frames: [_pic('')]),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: _Harness(cam: cam, onCode: (_) async => null),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.takeException(), isNull);
          await _settle(tester);
        }
      });
    }
  });

  group('the Windows Sync screen', () {
    tearDown(() => PlatformInfo.override = null);

    Future<void> pumpScreen(WidgetTester tester, AppPlatform platform, {FakeWebcam? cam, List<String>? paired}) async {
      PlatformInfo.override = platform;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            desktopSyncProvider.overrideWith(() => _FakeDesktopSync(paired)),
            openConflictsProvider.overrideWith((ref) => Stream.value(0)),
            webcamSourceFactoryProvider.overrideWithValue(() => cam ?? FakeWebcam(result: WebcamOpen.none)),
          ],
          child: const MaterialApp(home: DesktopSyncScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('on Windows there is a Scan with webcam button next to Paste', (tester) async {
      await pumpScreen(tester, AppPlatform.windows);
      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Scan with webcam'), findsOneWidget);
    });

    testWidgets('on a phone or elsewhere the button is not there', (tester) async {
      await pumpScreen(tester, AppPlatform.android);
      expect(find.text('Scan with webcam'), findsNothing);
      await pumpScreen(tester, AppPlatform.other);
      expect(find.text('Scan with webcam'), findsNothing);
    });

    testWidgets('a scanned code fills the box and pairs through the same path as Pair', (tester) async {
      final paired = <String>[];
      final cam = FakeWebcam(frames: [_pic(pairingTextForTests)]);
      await pumpScreen(tester, AppPlatform.windows, cam: cam, paired: paired);
      await tester.tap(find.text('Scan with webcam'));
      await tester.pump();
      // The dialog's decode is the real one (an isolate), so give it real time.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(milliseconds: 600));
      // Bytes of text are not a picture, so the real decoder finds nothing: the dialog is still looking.
      expect(find.text('Scan the code on your phone'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(paired, isEmpty);
    });

    testWidgets('Paste instead closes the dialog and pastes the clipboard', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') return {'text': pairingTextForTests};
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await pumpScreen(tester, AppPlatform.windows);
      await tester.tap(find.text('Scan with webcam'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Paste instead'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Scan the code on your phone'), findsNothing);
      expect(find.text(pairingTextForTests), findsOneWidget);
    });
  });
}

/// The Windows sync controller with nothing behind it: not paired, and it writes down what it was asked to pair.
class _FakeDesktopSync extends DesktopSyncController {
  final List<String>? paired;
  _FakeDesktopSync(this.paired);

  @override
  DesktopSyncState build() => const DesktopSyncState(loaded: true);

  @override
  Future<Object?> pair(String codeText) async {
    paired?.add(codeText);
    return null;
  }
}
