import 'package:card_organizer/app/app.dart';
import 'package:card_organizer/app/providers.dart';
import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/links/link_launcher.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late List<Uri> opened;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    opened = [];
  });
  // Closing inside the fake-async test zone never completes, so close here.
  tearDown(() => db.close());

  /// Database writes before the UI starts run in real async.
  Future<T?> seed<T>(WidgetTester tester, Future<T> Function(ContactsRepository repo) fn) =>
      tester.runAsync(() => fn(ContactsRepository(db)));

  Future<void> start(WidgetTester tester, {String at = '/'}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          launcherProvider.overrideWithValue(
            LinkLauncher((u) async {
              opened.add(u);
              return true;
            }),
          ),
          regionProvider.overrideWith((ref) => Stream.value('US')),
        ],
        child: CardOrganizerApp(initialLocation: at, showOnboarding: false),
      ),
    );
    await tester.pumpAndSettle();
  }

  // drift cancels stream queries on a short timer after the widget tree goes away.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('empty library shows the add prompt', (tester) async {
    await start(tester);
    expect(find.text('No contacts yet'), findsOneWidget);
    expect(find.text('0 people across 0 companies'), findsOneWidget);
    expect(find.text('Scan a card'), findsOneWidget);
    expect(find.text('Add by hand'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('add a contact by hand, then call and email from detail', (tester) async {
    await start(tester);
    await tester.tap(find.byTooltip('Add contact'));
    await tester.pumpAndSettle();
    expect(find.text('Scan a card'), findsWidgets);
    expect(find.text('Import card photos'), findsOneWidget);
    await tester.tap(find.text('Add by hand').last);
    await tester.pumpAndSettle();
    expect(find.text('New contact'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'First name'), 'Priya');
    await tester.enterText(find.widgetWithText(TextFormField, 'Last name'), 'Nambiar');
    await tester.enterText(find.widgetWithText(TextFormField, 'Company'), 'Halden Tooling Group');
    await tester.enterText(find.widgetWithText(TextFormField, 'Phone number'), '330 555 0142');
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'p.nambiar@haldentooling.example');
    await tester.pumpAndSettle();
    expect(find.textContaining('Saved as +1'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Lands on the detail screen.
    expect(find.text('Priya Nambiar'), findsOneWidget);
    expect(find.text('Halden Tooling Group'), findsWidgets);

    await tester.tap(find.text('Call'));
    await tester.tap(find.text('Email').first);
    await tester.pumpAndSettle();
    expect(opened.map((u) => u.toString()), ['tel:+13305550142', 'mailto:p.nambiar@haldentooling.example']);
    await finish(tester);
  });

  testWidgets('search narrows the list; no match shows the empty search state', (tester) async {
    await seed(tester, (repo) async {
      await repo.save(ContactDraft(first: 'Priya', last: 'Nambiar', company: 'Halden Tooling'));
      await repo.save(ContactDraft(first: 'Marcus', last: 'Oyelaran', company: 'Calder Hydraulics'));
    });
    await start(tester);
    expect(find.text('Priya Nambiar'), findsOneWidget);
    expect(find.text('Marcus Oyelaran'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'calder');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Priya Nambiar'), findsNothing);
    expect(find.text('Marcus Oyelaran'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('delete from detail with undo', (tester) async {
    final id = await seed(tester, (repo) => repo.save(ContactDraft(first: 'Jo', last: 'Park')));
    await start(tester);
    await tester.tap(find.text('Jo Park'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(find.text('No contacts yet'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Jo Park'), findsOneWidget);
    expect(await tester.runAsync(() => ContactsRepository(db).loadDetail(id!)), isNotNull);
    await finish(tester);
  });

  testWidgets('web check uses the chosen search engine', (tester) async {
    final id = await seed(
      tester,
      (repo) => repo.save(ContactDraft(first: 'Priya', last: 'Nambiar', company: 'Halden Tooling Group')),
    );
    await start(tester, at: '/contact/${id!}');
    await tester.scrollUntilVisible(find.text('Check on web'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Check on web'));
    await tester.pumpAndSettle();
    expect(opened.single.toString(), 'https://www.google.com/search?q=Priya+Nambiar+Halden+Tooling+Group');
    await finish(tester);
  });

  testWidgets('drawer lists every destination and later ones show their version', (tester) async {
    await start(tester);
    tester.view.physicalSize = const Size(1170, 3600); // tall enough that the drawer list is fully built
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    for (final label in [
      'Events',
      'Career moves',
      'Scan cards',
      'Review queue',
      'Follow-ups',
      'Duplicates',
      'Tags',
      'Import',
      'Export and backup',
      'Sync to desktop',
      'My card',
      'Settings',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.tap(find.text('Tags'));
    await tester.pumpAndSettle();
    expect(find.text('Tags'), findsWidgets);
    await finish(tester);
  });
}
