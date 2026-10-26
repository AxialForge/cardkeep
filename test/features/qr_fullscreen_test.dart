import 'package:card_organizer/features/sync/qr_fullscreen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

class _FakeBrightness implements QrBrightness {
  final calls = <String>[];
  @override
  Future<void> max() async => calls.add('max');
  @override
  Future<void> restore() async => calls.add('restore');
}

void main() {
  Future<void> open(WidgetTester tester, _FakeBrightness b) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showQrFullScreen(context, data: 'cardkeep-sync:test', brightness: b),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens big on white at full brightness, with the hint', (tester) async {
    final b = _FakeBrightness();
    await open(tester, b);
    expect(find.byKey(const Key('qr-fullscreen')), findsOneWidget);
    expect(b.calls, ['max']);
    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr.size, greaterThan(300));
    expect(qr.backgroundColor, Colors.white);
    expect(tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor, Colors.white);
    expect(find.textContaining('40 to 60 cm'), findsOneWidget);
    expect(find.textContaining('Tap anywhere to close'), findsOneWidget);
  });

  testWidgets('a tap closes it and the brightness goes back', (tester) async {
    final b = _FakeBrightness();
    await open(tester, b);
    await tester.tap(find.byKey(const Key('qr-fullscreen')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('qr-fullscreen')), findsNothing);
    expect(b.calls, ['max', 'restore']);
  });

  testWidgets('on a small screen the code is no larger than the screen allows', (tester) async {
    final b = _FakeBrightness();
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: QrFullScreen(data: 'x', brightness: b)),
    );
    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr.size, lessThanOrEqualTo(300));
    expect(tester.takeException(), isNull);
  });
}
