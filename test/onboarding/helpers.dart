import 'package:card_organizer/app/providers.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/features/onboarding/content/content_model.dart';
import 'package:card_organizer/features/onboarding/onboarding_providers.dart';
import 'package:card_organizer/features/onboarding/permission_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A permission service whose answers the test chooses.
class FakePermissions implements PermissionService {
  PermState camera;
  PermState notifications;

  /// What a request answers (per kind); default granted.
  PermState Function(PermKind) onRequest = (_) => PermState.granted;
  final requested = <PermKind>[];
  var openedSettings = 0;

  FakePermissions({this.camera = PermState.notAsked, this.notifications = PermState.notAsked});

  @override
  Future<PermState> status(PermKind kind) async => kind == PermKind.camera ? camera : notifications;

  @override
  Future<PermState> request(PermKind kind) async {
    requested.add(kind);
    final s = onRequest(kind);
    if (kind == PermKind.camera) {
      camera = s;
    } else {
      notifications = s;
    }
    return s;
  }

  @override
  Future<void> openSettings() async => openedSettings++;
}

AppDatabase memoryDb() => AppDatabase(NativeDatabase.memory());

/// Phone-sized view (360 x 640 dp) with animations off so the tree settles.
void smallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1280);
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
  });
}

/// Pumps [routes] at [at] with the standard overrides. [textScale] 2 = 200% text.
Future<GoRouter> pumpRouterApp(
  WidgetTester tester, {
  required AppDatabase db,
  required List<GoRoute> routes,
  String at = '/',
  FakePermissions? permissions,
  double textScale = 1,
  List<Override> extra = const [],
}) async {
  final router = GoRouter(initialLocation: at, routes: routes);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        regionProvider.overrideWith((ref) => Stream.value('US')),
        permissionServiceProvider.overrideWithValue(permissions ?? FakePermissions()),
        appFolderLabelProvider.overrideWith((ref) async => '/data/CardKeep'),
        ...extra,
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  return router;
}

/// Drift cancels stream queries on a short timer once the tree is gone.
Future<void> finishApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// Runs real async work (database writes) and lets the UI catch up.
Future<T?> real<T>(WidgetTester tester, Future<T> Function() fn) async {
  final out = await tester.runAsync(fn);
  await tester.pump(const Duration(milliseconds: 100));
  return out;
}

/// Scrolls [f] into view (building it first if a lazy list has not yet), then taps it.
Future<void> tapVisible(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(f);
}
