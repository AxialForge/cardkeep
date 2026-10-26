import 'package:card_organizer/app/app.dart';
import 'package:card_organizer/app/providers.dart';
import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/platform/platform_info.dart';
import 'package:card_organizer/features/desktop/desktop_root.dart';
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    PlatformInfo.override = AppPlatform.windows;
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() {
    PlatformInfo.override = null;
    return db.close();
  });

  Future<void> seed(WidgetTester tester) => tester.runAsync(() async {
    final repo = ContactsRepository(db);
    await repo.save(ContactDraft(first: 'Priya', last: 'Nambiar', company: 'Brightline'));
    await repo.save(ContactDraft(first: 'Sam', last: 'Okafor', company: 'Orbit Medical'));
  });

  Future<void> start(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db), regionProvider.overrideWith((ref) => Stream.value('US'))],
        child: const CardOrganizerApp(showOnboarding: false),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a wide window shows the list and a contact side by side', (tester) async {
    await seed(tester);
    await start(tester, const Size(1400, 900));
    expect(find.text('Choose a contact'), findsOneWidget);
    expect(find.text('Priya Nambiar'), findsOneWidget);

    await tester.tap(find.text('Priya Nambiar'));
    await tester.pumpAndSettle();
    // Still on the home screen: the contact opened in the right-hand pane.
    expect(find.text('Choose a contact'), findsNothing);
    expect(find.text('Sam Okafor'), findsOneWidget, reason: 'the list stays on the left');
    expect(find.byTooltip('Back'), findsNothing, reason: 'no Back button in the pane');
    expect(find.text('Brightline'), findsWidgets);

    await tester.tap(find.text('Sam Okafor'));
    await tester.pumpAndSettle();
    expect(find.text('Orbit Medical'), findsWidgets);
    await finish(tester);
  });

  testWidgets('a narrow window is the phone layout: tapping opens a page with Back', (tester) async {
    await seed(tester);
    await start(tester, const Size(700, 900));
    expect(find.text('Choose a contact'), findsNothing);
    await tester.tap(find.text('Priya Nambiar'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('no camera or NFC entries on Windows', (tester) async {
    await start(tester, const Size(1400, 900));
    expect(find.text('Scan card'), findsNothing, reason: 'no scan button without a camera');
    await tester.tap(find.byTooltip('Add contact'));
    await tester.pumpAndSettle();
    expect(find.text('Scan a card'), findsNothing);
    expect(find.text('Tap an NFC card'), findsNothing);
    expect(find.text('Sweep across cards'), findsNothing);
    expect(find.text('Add by hand'), findsWidgets);
    expect(find.text('Import card images from a folder'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('the empty library points to the phone', (tester) async {
    await start(tester, const Size(1400, 900));
    expect(find.text('No contacts yet'), findsOneWidget);
    expect(find.text('Sync with phone'), findsOneWidget);
    expect(find.text('Scan a card'), findsNothing);
    await finish(tester);
  });

  testWidgets('Ctrl+N opens a new contact and Esc goes back', (tester) async {
    await start(tester, const Size(1400, 900));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('New contact'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Ctrl+F puts the cursor in the search box', (tester) async {
    await seed(tester);
    await start(tester, const Size(1400, 900));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(isTypingIn(FocusManager.instance.primaryFocus), isTrue, reason: 'the cursor is in the search box');
    await tester.enterText(find.byType(TextField).first, 'sam');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Sam Okafor'), findsOneWidget);
    expect(find.text('Priya Nambiar'), findsNothing);
    await finish(tester);
  });

  testWidgets('right-click on a contact offers Open, Edit, Select and Delete', (tester) async {
    await seed(tester);
    await start(tester, const Size(1400, 900));
    final row = tester.getCenter(find.text('Priya Nambiar'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await mouse.down(row);
    await mouse.up();
    await tester.pumpAndSettle();
    for (final label in ['Open', 'Edit', 'Select', 'Delete']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a contact'), findsNothing);
    await finish(tester);
  });
}
