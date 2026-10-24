import 'dart:async';

import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/settings/settings_repository.dart';
import 'package:card_organizer/features/onboarding/content/content_model.dart';
import 'package:card_organizer/features/onboarding/content/help_content.dart';
import 'package:card_organizer/features/onboarding/content/welcome_content.dart';
import 'package:card_organizer/features/onboarding/lesson_art.dart';
import 'package:card_organizer/features/onboarding/onboarding_gate.dart';
import 'package:card_organizer/features/onboarding/onboarding_pages.dart';
import 'package:card_organizer/features/onboarding/onboarding_screen.dart';
import 'package:card_organizer/features/onboarding/permission_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'helpers.dart';

int get _pageCount => welcomePages.length + permissionCards.length + 3 + lessons.length + 1;

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  List<GoRoute> tourRoutes({bool replay = false, int page = 0}) => [
    GoRoute(
      path: '/',
      builder: (_, _) => const Scaffold(body: Center(child: Text('Contacts home'))),
    ),
    GoRoute(
      path: '/scan',
      builder: (_, _) => const Scaffold(body: Text('Scanner')),
    ),
    GoRoute(
      path: '/import',
      builder: (_, _) => const Scaffold(body: Text('Import screen')),
    ),
    GoRoute(
      path: '/welcome',
      builder: (_, s) => OnboardingScreen(replay: s.uri.queryParameters['replay'] == '1', startPage: page),
    ),
  ];

  group('the tour at 200% text on a 360 x 640 phone', () {
    test('there are nineteen pages: 4 welcome, 3 permissions, 3 set-up, 8 lessons, 1 finale', () {
      expect(_pageCount, 19);
    });

    for (var i = 0; i < 19; i++) {
      testWidgets('page ${i + 1} fits without overflow and announces its step', (tester) async {
        smallPhone(tester);
        final semantics = tester.ensureSemantics();
        await pumpRouterApp(
          tester,
          db: db,
          routes: tourRoutes(page: i),
          at: '/welcome',
          textScale: 2,
        );
        expect(tester.takeException(), isNull, reason: 'overflow or build error on page ${i + 1}');
        expect(find.bySemanticsLabel(RegExp('^Step ${i + 1} of 19')), findsOneWidget);
        // A scroll view can always reach the bottom of the page.
        await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -2000));
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
        semantics.dispose();
        await finishApp(tester);
      });
    }

    testWidgets('the same pages fit at normal size too', (tester) async {
      smallPhone(tester);
      for (final i in [0, 4, 7, 9, 12, 18]) {
        await pumpRouterApp(
          tester,
          db: db,
          routes: tourRoutes(page: i),
          at: '/welcome',
        );
        expect(tester.takeException(), isNull, reason: 'page ${i + 1}');
        await finishApp(tester);
      }
    });
  });

  group('every page can be reached and left', () {
    testWidgets('Next walks through all nineteen pages and Back returns', (tester) async {
      smallPhone(tester);
      await pumpRouterApp(tester, db: db, routes: tourRoutes(), at: '/welcome', textScale: 1);
      expect(find.text('Meet CardKeep'), findsOneWidget);
      for (var n = 1; n < _pageCount - 1; n++) {
        await tapVisible(tester, find.byType(FilledButton).last);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull, reason: 'moving to page ${n + 1}');
      }
      await tapVisible(tester, find.byType(FilledButton).last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('You\'re ready'), findsOneWidget);
      await tapVisible(tester, find.text('Back'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(lessons.last.title), findsWidgets);
      await finishApp(tester);
    });

    testWidgets('the system back button steps back one page, never out of the tour', (tester) async {
      smallPhone(tester);
      await pumpRouterApp(tester, db: db, routes: tourRoutes(page: 3), at: '/welcome');
      expect(find.text('How this tour works'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('What CardKeep keeps, and who can see it'), findsOneWidget);
      expect(find.text('Contacts home'), findsNothing);
      await finishApp(tester);
    });

    testWidgets('back on the first page asks before leaving', (tester) async {
      smallPhone(tester);
      await pumpRouterApp(tester, db: db, routes: tourRoutes(), at: '/welcome');
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Skip the tour?'), findsOneWidget);
      await tapVisible(tester, find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Meet CardKeep'), findsOneWidget);
      await finishApp(tester);
    });

    testWidgets('swiping moves between welcome pages', (tester) async {
      smallPhone(tester);
      await pumpRouterApp(tester, db: db, routes: tourRoutes(), at: '/welcome');
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Your privacy, precisely'), findsOneWidget);
      await finishApp(tester);
    });
  });

  group('skipping', () {
    testWidgets('Skip tour asks, then marks the tour done, turns tips off and opens Contacts', (tester) async {
      smallPhone(tester);
      await pumpRouterApp(tester, db: db, routes: tourRoutes(), at: '/welcome');
      await tapVisible(tester, find.text('Skip tour'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Skip the tour?'), findsOneWidget);
      await tapVisible(tester, find.text('Skip'));
      await tester.pump(const Duration(milliseconds: 100));
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(milliseconds: 400));
      final s = SettingsRepository(db);
      expect(await tester.runAsync(s.onboardingVersion), tourVersion);
      expect(await tester.runAsync(s.tipsEnabled), isFalse);
      expect(await tester.runAsync(s.autoBackup), isFalse, reason: 'a quick skip never turns backups on');
      expect(find.text('Contacts home'), findsOneWidget);
      await finishApp(tester);
    });

    testWidgets('keep going leaves everything as it was', (tester) async {
      smallPhone(tester);
      await pumpRouterApp(tester, db: db, routes: tourRoutes(), at: '/welcome');
      await tapVisible(tester, find.text('Skip tour'));
      await tester.pump(const Duration(milliseconds: 300));
      await tapVisible(tester, find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(await tester.runAsync(SettingsRepository(db).onboardingVersion), isNull);
      expect(find.text('Meet CardKeep'), findsOneWidget);
      await finishApp(tester);
    });
  });

  group('the finale', () {
    testWidgets('Start empty finishes: tour done, tips on, Contacts', (tester) async {
      smallPhone(tester);
      await pumpRouterApp(
        tester,
        db: db,
        routes: tourRoutes(page: _pageCount - 1),
        at: '/welcome',
      );
      await tapVisible(tester, find.text('Start empty'));
      await tester.pump(const Duration(milliseconds: 100));
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(milliseconds: 400));
      final s = SettingsRepository(db);
      expect(await tester.runAsync(s.onboardingVersion), tourVersion);
      expect(await tester.runAsync(s.tipsEnabled), isTrue);
      expect(find.text('Contacts home'), findsOneWidget);
      await finishApp(tester);
    });

    testWidgets('Start with demo data adds the six demo contacts', (tester) async {
      smallPhone(tester);
      await pumpRouterApp(
        tester,
        db: db,
        routes: tourRoutes(page: _pageCount - 1),
        at: '/welcome',
      );
      await tester.scrollUntilVisible(
        find.text('Start with demo data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tapVisible(tester, find.text('Start with demo data'));
      await tester.pump(const Duration(milliseconds: 100));
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pump(const Duration(milliseconds: 400));
      final n = await tester.runAsync(
        () async => (await db.customSelect('SELECT COUNT(*) AS c FROM people').getSingle()).read<int>('c'),
      );
      expect(n, 6);
      expect(find.text('Contacts home'), findsOneWidget);
      await finishApp(tester);
    });

    testWidgets('Scan your first card finishes and opens the scanner on top of Contacts', (tester) async {
      smallPhone(tester);
      await pumpRouterApp(
        tester,
        db: db,
        routes: tourRoutes(page: _pageCount - 1),
        at: '/welcome',
      );
      await tapVisible(tester, find.text('Scan your first card'));
      await tester.pump(const Duration(milliseconds: 100));
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Scanner'), findsOneWidget);
      await finishApp(tester);
    });

    testWidgets('the import how-tos for Google, Outlook, iPhone and LinkedIn expand', (tester) async {
      smallPhone(tester);
      await pumpRouterApp(
        tester,
        db: db,
        routes: tourRoutes(page: _pageCount - 1),
        at: '/welcome',
      );
      await tester.scrollUntilVisible(
        find.text('How to bring contacts from…'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tapVisible(tester, find.text('How to bring contacts from…'));
      await tester.pump(const Duration(milliseconds: 400));
      for (final h in importHowTos) {
        expect(find.text(h.source), findsOneWidget);
      }
      await finishApp(tester);
    });

    testWidgets('replay: nothing is marked done and Done goes back', (tester) async {
      smallPhone(tester);
      final router = await pumpRouterApp(
        tester,
        db: db,
        routes: tourRoutes(page: _pageCount - 1),
        at: '/',
      );
      unawaited(router.push('/welcome?replay=1'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('That\'s the tour'), findsOneWidget);
      await tapVisible(tester, find.text('Done'));
      await tester.pump(const Duration(milliseconds: 100));
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(await tester.runAsync(SettingsRepository(db).onboardingVersion), isNull);
      expect(find.text('Contacts home'), findsOneWidget);
      await finishApp(tester);
    });
  });

  group('set-up choices', () {
    testWidgets('the weekly backup is on in the tour but only saved when you leave that page', (tester) async {
      smallPhone(tester);
      final s = SettingsRepository(db);
      await pumpRouterApp(tester, db: db, routes: tourRoutes(page: 9), at: '/welcome');
      expect(find.text('Your safety net'), findsOneWidget);
      expect(
        find.text('/data/CardKeep/backups (private to CardKeep; open them from Export and backup).'),
        findsOneWidget,
      );
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
      expect(await tester.runAsync(s.autoBackup), isFalse, reason: 'not saved yet');
      await tapVisible(tester, find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 100));
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(await tester.runAsync(s.autoBackup), isTrue);
      await finishApp(tester);
    });

    testWidgets('switching it off on that page is kept', (tester) async {
      smallPhone(tester);
      final s = SettingsRepository(db);
      await pumpRouterApp(tester, db: db, routes: tourRoutes(page: 9), at: '/welcome');
      await tapVisible(tester, find.byType(SwitchListTile));
      await tester.pump(const Duration(milliseconds: 200));
      await tapVisible(tester, find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 100));
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 300)));
      expect(await tester.runAsync(s.autoBackup), isFalse);
      await finishApp(tester);
    });

    testWidgets('lead ratings, career tracking and auto-save toggles apply at once', (tester) async {
      smallPhone(tester);
      final s = SettingsRepository(db);
      await pumpRouterApp(tester, db: db, routes: tourRoutes(page: 8), at: '/welcome');
      final switches = find.byType(SwitchListTile);
      expect(switches, findsNWidgets(3));
      await tapVisible(tester, switches.at(0));
      await tester.pump(const Duration(milliseconds: 50));
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 100)));
      expect(await tester.runAsync(() => s.watchLeadsEnabled().first), isFalse);
      await tapVisible(tester, switches.at(1));
      await tester.pump(const Duration(milliseconds: 50));
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 100)));
      expect(await tester.runAsync(() => s.watchTrackCareer().first), isFalse);
      await tapVisible(tester, switches.at(2));
      await tester.pump(const Duration(milliseconds: 50));
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 100)));
      expect(await tester.runAsync(s.autoSaveClean), isFalse);
      await finishApp(tester);
    });

    testWidgets('the live examples change with the auto-save choice', (tester) async {
      smallPhone(tester);
      await pumpRouterApp(tester, db: db, routes: tourRoutes(page: 8), at: '/welcome');
      expect(find.text('Goes straight to Contacts'), findsOneWidget);
      await tapVisible(tester, find.byType(SwitchListTile).at(2));
      await tester.pump(const Duration(milliseconds: 50));
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 100)));
      expect(find.text('Goes straight to Contacts'), findsNothing);
      expect(find.text('Waits in the Review queue'), findsNWidgets(2));
      await finishApp(tester);
    });

    testWidgets('name order and region can be chosen on the look page', (tester) async {
      smallPhone(tester);
      await pumpRouterApp(tester, db: db, routes: tourRoutes(page: 7), at: '/welcome');
      expect(find.text('Sort names by'), findsOneWidget);
      expect(find.text('Phone region'), findsOneWidget);
      expect(find.text('Match phone'), findsOneWidget);
      expect(find.text('Navy and brass'), findsOneWidget);
      await finishApp(tester);
    });
  });

  group('permission cards', () {
    testWidgets('the camera card explains first, and asks only when you tap Allow', (tester) async {
      smallPhone(tester);
      final perms = FakePermissions();
      await pumpRouterApp(tester, db: db, routes: tourRoutes(page: 4), at: '/welcome', permissions: perms);
      expect(find.text('Camera'), findsWidgets);
      for (final h in ['WHY WE ASK', 'WHAT CARDKEEP NEVER DOES', 'IF YOU SAY NO', 'CHANGE IT LATER']) {
        expect(find.text(h), findsOneWidget, reason: h);
      }
      expect(perms.requested, isEmpty, reason: 'nothing asked yet');
      expect(find.text('Not asked yet'), findsOneWidget);
      await tapVisible(tester, find.text('Allow camera'));
      await tester.pump(const Duration(milliseconds: 100));
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(perms.requested, [PermKind.camera]);
      expect(find.text('Allowed'), findsOneWidget);
      expect(find.text('Allow camera'), findsNothing);
      await finishApp(tester);
    });

    testWidgets('a refusal says so and lets you ask again, or carry on', (tester) async {
      smallPhone(tester);
      final perms = FakePermissions()..onRequest = (_) => PermState.denied;
      await pumpRouterApp(tester, db: db, routes: tourRoutes(page: 5), at: '/welcome', permissions: perms);
      await tapVisible(tester, find.text('Allow notifications'));
      await tester.pump(const Duration(milliseconds: 100));
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(find.text('Not allowed'), findsOneWidget);
      expect(find.text('Ask again'), findsOneWidget);
      expect(find.textContaining('Not now is fine'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      await finishApp(tester);
    });

    testWidgets('a blocked permission offers the phone settings and nothing else to ask', (tester) async {
      smallPhone(tester);
      final perms = FakePermissions(camera: PermState.blocked);
      await pumpRouterApp(tester, db: db, routes: tourRoutes(page: 4), at: '/welcome', permissions: perms);
      expect(find.text('Blocked in phone settings'), findsOneWidget);
      expect(find.text('Allow camera'), findsNothing);
      await tapVisible(tester, find.text('Open phone settings'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(perms.openedSettings, 1);
      await finishApp(tester);
    });

    testWidgets('an already-allowed permission is shown as allowed', (tester) async {
      smallPhone(tester);
      final perms = FakePermissions(notifications: PermState.granted);
      await pumpRouterApp(tester, db: db, routes: tourRoutes(page: 5), at: '/welcome', permissions: perms);
      expect(find.text('Allowed'), findsOneWidget);
      expect(find.text('Allow notifications'), findsNothing);
      await finishApp(tester);
    });

    testWidgets('the NFC card has nothing to allow and says contacts are never read', (tester) async {
      smallPhone(tester);
      final perms = FakePermissions();
      await pumpRouterApp(tester, db: db, routes: tourRoutes(page: 6), at: '/welcome', permissions: perms);
      expect(find.textContaining('Allow'), findsNothing);
      expect(find.textContaining('never asks to read your phone'), findsOneWidget);
      expect(perms.requested, isEmpty);
      await finishApp(tester);
    });
  });

  group('lessons', () {
    testWidgets('each lesson page shows its steps, tip and a Try it that opens the screen', (tester) async {
      smallPhone(tester);
      const first = 4 + 3 + 3;
      for (var i = 0; i < lessons.length; i++) {
        await pumpRouterApp(
          tester,
          db: db,
          routes: tourRoutes(page: first + i),
          at: '/welcome',
        );
        final l = lessons[i];
        expect(find.text(l.title), findsOneWidget, reason: l.id);
        expect(find.textContaining('Lesson ${i + 1} of 8'), findsOneWidget);
        expect(find.byType(StepTile), findsNWidgets(l.steps.length));
        expect(find.byType(TryItButton), l.tryRoute == null ? findsNothing : findsOneWidget, reason: l.id);
        if (l.tryRoute != null) {
          await tester.scrollUntilVisible(find.byType(TryItButton), 200, scrollable: find.byType(Scrollable).first);
          expect(find.descendant(of: find.byType(TryItButton), matching: find.text(l.tryLabel!)), findsOneWidget);
        }
        await finishApp(tester);
      }
    });
  });

  group('illustrations', () {
    testWidgets('every illustration draws through a whole loop without errors', (tester) async {
      tester.view.physicalSize = const Size(720, 1280);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      for (final art in Art.values) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: LessonArt(art))));
        for (var ms = 0; ms <= 5400; ms += 300) {
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull, reason: '${art.name} at $ms ms');
        }
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('with remove animations on, an illustration stands still on its finished frame', (tester) async {
      smallPhone(tester);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LessonArt(Art.scanOne))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
