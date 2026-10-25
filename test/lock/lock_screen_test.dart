import 'package:card_organizer/app/theme.dart';
import 'package:card_organizer/core/lock/auth_service.dart';
import 'package:card_organizer/core/lock/lock_controller.dart';
import 'package:card_organizer/features/lock/lock_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth implements AuthService {
  AuthResult next = AuthResult.cancelled;
  int asked = 0;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<AuthResult> authenticate(String reason) async {
    asked++;
    return next;
  }
}

void main() {
  // The settings streams are faked: a real database stream leaves a timer behind
  // that a widget test does not allow. The lock logic itself is in lock_controller_test.
  Future<_Auth> pump(WidgetTester tester, {double scale = 1}) async {
    final auth = _Auth();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          initialLockedProvider.overrideWithValue(true),
          appLockProvider.overrideWith((ref) => Stream.value(true)),
          lockAfterProvider.overrideWith((ref) => Stream.value(1)),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), size: const Size(360, 640)),
            child: LockGate(child: child!),
          ),
          home: const Scaffold(body: Center(child: Text('Secret contacts'))),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return auth;
  }

  testWidgets('locked: the library is hidden, the lock screen shows and asks the phone once', (tester) async {
    final auth = await pump(tester);
    expect(find.text('CardKeep is locked'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.text('Secret contacts'), findsNothing, reason: 'nothing from the library is visible while locked');
    expect(
      find.text('Secret contacts', skipOffstage: false),
      findsOneWidget,
      reason: 'but the app underneath stays alive',
    );
    expect(auth.asked, 1, reason: 'asks as soon as it opens');
    expect(find.text('That did not work. Tap Unlock to try again.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Unlock tries again and opens the app when the phone says yes', (tester) async {
    final auth = await pump(tester);
    auth.next = AuthResult.success;
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    await tester.pump();
    expect(find.text('CardKeep is locked'), findsNothing);
    expect(find.text('Secret contacts'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the lock screen fits a small screen at 200% text with no overflow', (tester) async {
    await pump(tester, scale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('Unlock'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the lock screen is described for TalkBack', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    expect(find.bySemanticsLabel(RegExp('CardKeep is locked')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('CardKeep logo')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  });
}
