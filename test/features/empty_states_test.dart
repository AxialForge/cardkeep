import 'package:card_organizer/app/app.dart';
import 'package:card_organizer/app/providers.dart';
import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// S15.3: every empty list says what it is and offers one clear next step.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> start(WidgetTester tester, String at) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db), regionProvider.overrideWith((ref) => Stream.value('US'))],
        child: CardOrganizerApp(initialLocation: at, showOnboarding: false),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  const cases = <(String route, String title, String action)>[
    ('/', 'No contacts yet', 'Scan a card'),
    ('/tags', 'No tags yet', 'New tag'),
    ('/events', 'No events yet', 'Add an event'),
    ('/followups', 'All caught up', 'Open Contacts'),
    ('/duplicates', 'No duplicates', 'Check again'),
    ('/career', 'Nothing to check', 'Scan a card'),
    ('/queue', 'Nothing to review', 'Scan a card'),
  ];

  for (final (route, title, action) in cases) {
    testWidgets('$route: "$title" offers "$action"', (tester) async {
      await start(tester, route);
      expect(find.text(title), findsOneWidget);
      expect(find.text(action), findsWidgets);
      await finish(tester);
    });
  }

  testWidgets('no matches offers to clear the search and brings the list back', (tester) async {
    await tester.runAsync(() => ContactsRepository(db).save(ContactDraft(first: 'Marcus', last: 'Oyelaran')));
    await start(tester, '/');
    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
    await tester.tap(find.text('Clear search and filters'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsNothing);
    expect(find.text('Marcus Oyelaran'), findsOneWidget);
    await finish(tester);
  });
}
