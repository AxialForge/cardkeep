import 'package:card_organizer/app/providers.dart';
import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/features/duplicates/duplicates_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phone test 0.7.1: the Undo message closed before it was tapped and the
/// merge could not be undone. Undo now also stays at the top of Duplicates.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> live(WidgetTester t) async => (await t.runAsync(
    () async =>
        (await db.customSelect('SELECT COUNT(*) AS n FROM people WHERE deleted_at IS NULL').getSingle()).read<int>('n'),
  ))!;

  /// Lets the database work (real async), then redraws.
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('Undo still works after the message has gone and the list rebuilt empty', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.runAsync(() async {
      final repo = ContactsRepository(db);
      for (var i = 0; i < 3; i++) {
        await repo.save(
          ContactDraft(first: 'Bridgette', last: 'Kipling', company: 'Enpress LLC', emails: ['b@enpress.example']),
        );
      }
    });
    await t.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: DuplicatesScreen()),
      ),
    );
    await settle(t);

    await t.tap(find.text('Merge all obvious duplicates'));
    await settle(t);
    await t.tap(find.text('Merge 2 contacts'));
    await settle(t);
    expect(await live(t), 1);
    expect(find.text('No duplicates'), findsOneWidget, reason: 'the list rebuilt empty');

    // Let the 5-second message close, as on the phone.
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
    expect(find.widgetWithText(SnackBarAction, 'Undo'), findsNothing);

    await t.tap(find.widgetWithText(TextButton, 'Undo'));
    await settle(t);
    expect(await live(t), 3, reason: 'every merged contact is back');
    expect(find.text('Merged 2 duplicates'), findsNothing, reason: 'the Undo panel goes away');
  });
}
