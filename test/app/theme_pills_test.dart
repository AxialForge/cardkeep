import 'package:card_organizer/app/providers.dart';
import 'package:card_organizer/app/theme.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/features/settings/theme_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../onboarding/helpers.dart';

void main() {
  Future<void> pumpPicker(WidgetTester tester, AppDatabase db, {double textScale = 1}) async {
    smallPhone(tester);
    await pumpRouterApp(
      tester,
      db: db,
      textScale: textScale,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(body: ListView(children: const [ThemePicker()])),
        ),
      ],
    );
  }

  testWidgets('six pills are listed, in order, at 200% font without overflow', (tester) async {
    final db = memoryDb();
    addTearDown(db.close);
    await pumpPicker(tester, db, textScale: 2);
    for (final name in ['CardKeep', 'Navy and brass', 'Harbor', 'Rosewater', 'Sage', 'Lamplight']) {
      final f = find.text(name);
      if (f.evaluate().isEmpty) {
        await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
      }
      expect(f, findsOneWidget, reason: name);
    }
    expect(tester.takeException(), isNull);
    await finishApp(tester);
  });

  testWidgets('tapping a pill\'s dark cluster saves that palette, Match phone keeps the look', (tester) async {
    final db = memoryDb();
    addTearDown(db.close);
    await pumpPicker(tester, db);
    final dark = find.byTooltip('Dark');
    // Pills are in family order: the sixth is Lamplight.
    await tester.scrollUntilVisible(find.text('Lamplight'), 200, scrollable: find.byType(Scrollable).first);
    expect(dark, findsAtLeastNWidgets(6));
    await tester.ensureVisible(dark.at(5));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(dark.at(5));
    await tester.pump(const Duration(milliseconds: 100));
    final saved = await real(tester, () => ProviderScopeReader.read(tester, db));
    expect(saved, 'lamplight');
    await finishApp(tester);
  });

  testWidgets('every new look draws the picker without errors in light and dark', (tester) async {
    final db = memoryDb();
    addTearDown(db.close);
    for (final p in AppPalette.all) {
      AppPalette.current = p;
      await pumpPicker(tester, db);
      expect(tester.takeException(), isNull, reason: p.id);
    }
    AppPalette.current = AppPalette.light;
    await finishApp(tester);
  });
}

/// Reads the saved theme straight from the settings table.
class ProviderScopeReader {
  static Future<String?> read(WidgetTester tester, AppDatabase db) async {
    final element = tester.element(find.byType(ThemePicker));
    final container = ProviderScope.containerOf(element);
    return container.read(settingsRepoProvider).watchTheme().first;
  }
}
