import 'package:card_organizer/app/app.dart';
import 'package:card_organizer/app/providers.dart';
import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/links/link_launcher.dart';
import 'package:card_organizer/core/settings/settings_repository.dart';
import 'package:card_organizer/features/onboarding/coach.dart';
import 'package:card_organizer/features/onboarding/content/help_content.dart';
import 'package:card_organizer/features/onboarding/help_screen.dart';
import 'package:card_organizer/features/onboarding/onboarding_gate.dart';
import 'package:card_organizer/features/onboarding/onboarding_pages.dart';
import 'package:card_organizer/features/onboarding/onboarding_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'helpers.dart';

class _Forced extends CoachForce {
  @override
  String? build() => 't1';
}

class _Host extends StatelessWidget {
  final List<CoachStep> steps;
  const _Host({required this.steps});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: CoachScope(
      tipId: 't1',
      delay: const Duration(milliseconds: 10),
      steps: steps,
      child: Column(
        children: [
          const SizedBox(height: 120),
          const CoachTarget(id: 'a', child: Text('Target A')),
          const SizedBox(height: 40),
          CoachTarget(
            id: 'b',
            child: FilledButton(onPressed: () {}, child: const Text('Target B')),
          ),
        ],
      ),
    ),
  );
}

const _steps = [
  CoachStep('a', 'First tip', 'Body one'),
  CoachStep('missing', 'Ghost tip', 'Never shown: its target is not on screen'),
  CoachStep('b', 'Second tip', 'Body two'),
];

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  List<GoRoute> hostRoutes([List<CoachStep> steps = _steps]) => [
    GoRoute(
      path: '/',
      builder: (_, _) => _Host(steps: steps),
    ),
  ];

  Future<void> settle(WidgetTester tester) async {
    await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 250)));
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('coach marks', () {
    testWidgets('tips off (the default before the tour is finished): nothing shows', (tester) async {
      smallPhone(tester);
      await pumpRouterApp(tester, db: db, routes: hostRoutes());
      await settle(tester);
      expect(find.text('First tip'), findsNothing);
      await finishApp(tester);
    });

    testWidgets('tips on: shows each step in turn, skips a missing target, then remembers', (tester) async {
      smallPhone(tester);
      await tester.runAsync(() => SettingsRepository(db).setTipsEnabled(true));
      await pumpRouterApp(tester, db: db, routes: hostRoutes());
      await settle(tester);
      expect(find.text('First tip'), findsOneWidget);
      expect(find.text('Body one'), findsOneWidget);
      expect(find.text('1 of 3'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Ghost tip'), findsNothing);
      expect(find.text('Second tip'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget, reason: 'the last visible step ends the tip');
      await tester.tap(find.text('Got it'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Second tip'), findsNothing);
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 100)));
      expect(await tester.runAsync(SettingsRepository(db).tipsSeen), {'t1'});
      await finishApp(tester);
    });

    testWidgets('a tip already seen does not show again', (tester) async {
      smallPhone(tester);
      await tester.runAsync(() async {
        final s = SettingsRepository(db);
        await s.setTipsEnabled(true);
        await s.markTipSeen('t1');
      });
      await pumpRouterApp(tester, db: db, routes: hostRoutes());
      await settle(tester);
      expect(find.text('First tip'), findsNothing);
      await finishApp(tester);
    });

    testWidgets('Skip closes the tip and counts it as seen', (tester) async {
      smallPhone(tester);
      await tester.runAsync(() => SettingsRepository(db).setTipsEnabled(true));
      await pumpRouterApp(tester, db: db, routes: hostRoutes());
      await settle(tester);
      await tester.tap(find.text('Skip'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('First tip'), findsNothing);
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 100)));
      expect(await tester.runAsync(SettingsRepository(db).tipsSeen), {'t1'});
      await finishApp(tester);
    });

    testWidgets('Try it forces the tip even when tips are off and it was seen, then clears the request', (
      tester,
    ) async {
      smallPhone(tester);
      await tester.runAsync(() => SettingsRepository(db).markTipSeen('t1'));
      await pumpRouterApp(tester, db: db, routes: hostRoutes(), extra: [coachForceProvider.overrideWith(_Forced.new)]);
      await settle(tester);
      expect(find.text('First tip'), findsOneWidget);
      final container = ProviderScope.containerOf(tester.element(find.byType(_Host)));
      expect(container.read(coachForceProvider), isNull);
      await finishApp(tester);
    });

    testWidgets('when no target is on screen nothing shows and the tip stays unseen', (tester) async {
      smallPhone(tester);
      await tester.runAsync(() => SettingsRepository(db).setTipsEnabled(true));
      await pumpRouterApp(tester, db: db, routes: hostRoutes(const [CoachStep('nope', 'Lost', 'x')]));
      await settle(tester);
      expect(find.text('Lost'), findsNothing);
      expect(await tester.runAsync(SettingsRepository(db).tipsSeen), isEmpty);
      await finishApp(tester);
    });

    testWidgets('the tip card reads as one announcement for TalkBack', (tester) async {
      smallPhone(tester);
      final semantics = tester.ensureSemantics();
      await tester.runAsync(() => SettingsRepository(db).setTipsEnabled(true));
      await pumpRouterApp(tester, db: db, routes: hostRoutes());
      await settle(tester);
      expect(find.bySemanticsLabel(RegExp(r'^Tip 1 of 3: First tip\. Body one')), findsOneWidget);
      semantics.dispose();
      await finishApp(tester);
    });
  });

  group('Help & tips', () {
    final opened = <Uri>[];
    setUp(opened.clear);

    List<GoRoute> helpRoutes() => [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('Home')),
      ),
      GoRoute(path: '/help', builder: (_, _) => const HelpScreen()),
      GoRoute(
        path: '/help/:id',
        builder: (_, s) => HelpArticleScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/scan',
        builder: (_, _) => const Scaffold(body: Text('Scanner')),
      ),
      GoRoute(
        path: '/welcome',
        builder: (_, s) => Scaffold(body: Text('Tour replay=${s.uri.queryParameters['replay']}')),
      ),
    ];

    Future<GoRouter> openHelp(WidgetTester tester, {double textScale = 1}) => pumpRouterApp(
      tester,
      db: db,
      routes: helpRoutes(),
      at: '/help',
      textScale: textScale,
      extra: [
        launcherProvider.overrideWithValue(
          LinkLauncher((u) async {
            opened.add(u);
            return true;
          }),
        ),
      ],
    );

    testWidgets('lists the quick actions and every group, with no demo option while there is no demo data', (
      tester,
    ) async {
      smallPhone(tester);
      await openHelp(tester);
      expect(find.text('Help & tips'), findsOneWidget);
      expect(find.text('Replay the tour'), findsOneWidget);
      expect(find.text('Reset tips'), findsOneWidget);
      expect(find.text('Remove demo data'), findsNothing);
      expect(find.text('START HERE'), findsOneWidget);
      expect(find.text('Scan one card'), findsOneWidget);
      await finishApp(tester);
    });

    testWidgets('typing narrows the list; nothing found says so; clear brings it back', (tester) async {
      smallPhone(tester);
      await openHelp(tester);
      await tester.enterText(find.byType(TextField), 'backups');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('How do backups work?'), findsOneWidget);
      expect(find.text('Scan one card'), findsNothing);
      expect(find.text('Replay the tour'), findsNothing, reason: 'actions hide while searching');
      await tester.enterText(find.byType(TextField), 'zebra quantum');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Nothing found'), findsOneWidget);
      await tapVisible(tester, find.text('Clear search'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Replay the tour'), findsOneWidget);
      await finishApp(tester);
    });

    testWidgets('an article opens with its steps; a lesson\'s Try it opens the screen and asks for its tip', (
      tester,
    ) async {
      smallPhone(tester);
      await openHelp(tester);
      final scan = lessons.first;
      await tapVisible(tester, find.text(scan.title));
      await tester.pump(const Duration(milliseconds: 400));
      for (final st in scan.steps) {
        expect(find.text(st.title), findsWidgets);
      }
      await tapVisible(tester, find.byType(TryItButton));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Scanner'), findsOneWidget);
      final container = ProviderScope.containerOf(tester.element(find.text('Scanner')));
      expect(container.read(coachForceProvider), 'scan');
      await finishApp(tester);
    });

    testWidgets('an unknown article id says so instead of crashing', (tester) async {
      smallPhone(tester);
      await pumpRouterApp(tester, db: db, routes: helpRoutes(), at: '/help/nope');
      expect(find.text('Not found'), findsOneWidget);
      await finishApp(tester);
    });

    testWidgets('Replay the tour opens the tour in replay mode', (tester) async {
      smallPhone(tester);
      await openHelp(tester);
      await tester.tap(find.text('Replay the tour'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Tour replay=1'), findsOneWidget);
      await finishApp(tester);
    });

    testWidgets('Report an issue opens the GitHub issues page', (tester) async {
      smallPhone(tester);
      await openHelp(tester);
      await tapVisible(tester, find.text('Report an issue'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(opened.map((u) => u.toString()), [issuesUrl]);
      await finishApp(tester);
    });

    testWidgets('Reset tips turns tips on and forgets what was seen', (tester) async {
      smallPhone(tester);
      await tester.runAsync(() => SettingsRepository(db).markTipSeen('contacts'));
      await openHelp(tester);
      await tester.tap(find.text('Reset tips'));
      await tester.pump(const Duration(milliseconds: 100));
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 200)));
      final s = SettingsRepository(db);
      expect(await tester.runAsync(s.tipsSeen), isEmpty);
      expect(await tester.runAsync(s.tipsEnabled), isTrue);
      expect(find.textContaining('Tips will show again'), findsOneWidget);
      await finishApp(tester);
    });

    testWidgets('Remove demo data appears when demo contacts exist, confirms, and removes them', (tester) async {
      smallPhone(tester);
      final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
      addTearDown(container.dispose);
      await tester.runAsync(() => container.read(demoDataProvider).add());
      await openHelp(tester);
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 100)));
      expect(find.text('Remove demo data'), findsOneWidget);
      expect(find.text('6 sample contacts tagged Demo'), findsOneWidget);
      await tester.tap(find.text('Remove demo data'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Remove demo data?'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pump(const Duration(milliseconds: 100));
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 400)));
      expect(await tester.runAsync(container.read(demoDataProvider).count), 0);
      expect(find.text('Remove demo data'), findsNothing);
      await finishApp(tester);
    });

    testWidgets('fits at 200% text on a small phone', (tester) async {
      smallPhone(tester);
      final semantics = tester.ensureSemantics();
      await openHelp(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel(RegExp('Search help')), findsWidgets);
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await finishApp(tester);
    });
  });

  group('the app on launch', () {
    Future<void> launch(WidgetTester tester, {bool onboarding = true}) async {
      smallPhone(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            regionProvider.overrideWith((ref) => Stream.value('US')),
            appFolderLabelProvider.overrideWith((ref) async => '/data/CardKeep'),
          ],
          child: CardOrganizerApp(showOnboarding: onboarding),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('a brand-new user lands in the tour', (tester) async {
      await launch(tester);
      expect(find.text('Meet CardKeep'), findsOneWidget);
      await finishApp(tester);
    });

    testWidgets('with the tour switched off (tests) a new user lands on Contacts', (tester) async {
      await launch(tester, onboarding: false);
      expect(find.text('No contacts yet'), findsOneWidget);
      await finishApp(tester);
    });

    testWidgets('a user who finished the tour goes straight to Contacts', (tester) async {
      await tester.runAsync(() => SettingsRepository(db).setOnboardingVersion(tourVersion));
      await launch(tester);
      expect(find.text('Meet CardKeep'), findsNothing);
      expect(find.text('No contacts yet'), findsOneWidget);
      await finishApp(tester);
    });

    testWidgets('someone upgrading with contacts gets the What\'s new sheet, not the tour', (tester) async {
      await tester.runAsync(() => ContactsRepository(db).save(ContactDraft(first: 'Dana', last: 'Reyes')));
      await launch(tester);
      expect(find.text("What's new in CardKeep"), findsOneWidget);
      expect(find.text('Meet CardKeep'), findsNothing);
      expect(find.text('Sweep scan'), findsOneWidget);
      await tapVisible(tester, find.text('Not now'));
      await tester.pump(const Duration(milliseconds: 100));
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 300)));
      final s = SettingsRepository(db);
      expect(await tester.runAsync(s.onboardingVersion), tourVersion);
      expect(await tester.runAsync(s.whatsNewSeen), tourVersion);
      expect(await tester.runAsync(s.tipsEnabled), isFalse);
      await finishApp(tester);
    });

    testWidgets('"Show me tips as I go" turns tips on without a tour', (tester) async {
      await tester.runAsync(() => ContactsRepository(db).save(ContactDraft(first: 'Dana', last: 'Reyes')));
      await launch(tester);
      await tapVisible(tester, find.text('Show me tips as I go'));
      await tester.pump(const Duration(milliseconds: 100));
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 300)));
      expect(await tester.runAsync(SettingsRepository(db).tipsEnabled), isTrue);
      expect(find.text('Meet CardKeep'), findsNothing);
      await finishApp(tester);
    });

    testWidgets('"Take the tour" opens it in replay mode and saves the choice first', (tester) async {
      await tester.runAsync(() => ContactsRepository(db).save(ContactDraft(first: 'Dana', last: 'Reyes')));
      await launch(tester);
      await tapVisible(tester, find.text('Take the tour'));
      await tester.pump(const Duration(milliseconds: 100));
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Meet CardKeep'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget, reason: 'replay mode');
      expect(await tester.runAsync(SettingsRepository(db).onboardingVersion), tourVersion);
      await finishApp(tester);
    });

    testWidgets('swiping the sheet away counts as Not now', (tester) async {
      await tester.runAsync(() => ContactsRepository(db).save(ContactDraft(first: 'Dana', last: 'Reyes')));
      await launch(tester);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 100));
      await real(tester, () => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text("What's new in CardKeep"), findsNothing);
      expect(await tester.runAsync(SettingsRepository(db).onboardingVersion), tourVersion);
      expect(await tester.runAsync(SettingsRepository(db).tipsEnabled), isFalse);
      await finishApp(tester);
    });
  });
}
