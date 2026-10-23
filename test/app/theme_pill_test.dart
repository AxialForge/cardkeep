import 'package:card_organizer/kit/theme_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pill selects the theme, each cluster pins its mode', (tester) async {
    var theme = 0, light = 0, dark = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThemePill(
            name: 'Orange',
            lightColors: const [Colors.white, Colors.orange, Colors.brown],
            darkColors: const [Colors.black, Colors.orange, Colors.white],
            surface: Colors.white,
            hairline: Colors.grey,
            ink: Colors.black,
            accent: Colors.orange,
            selected: true,
            pinned: ThemeMode.dark,
            onSelectTheme: () => theme++,
            onSelectLight: () => light++,
            onSelectDark: () => dark++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Orange'));
    await tester.tap(find.byTooltip('Light'));
    await tester.tap(find.byTooltip('Dark'));
    expect((theme, light, dark), (1, 1, 1));
  });

  testWidgets('pill is 64 dp tall and its zones are 60 x 56 dp', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThemePill(
            name: 'A very long theme name that must be cut with an ellipsis instead of wrapping',
            lightColors: const [Colors.white, Colors.orange, Colors.brown],
            darkColors: const [Colors.black, Colors.orange, Colors.white],
            surface: Colors.white,
            hairline: Colors.grey,
            ink: Colors.black,
            accent: Colors.orange,
            selected: false,
            pinned: null,
            onSelectTheme: () {},
            onSelectLight: () {},
            onSelectDark: () {},
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(InkWell).first).height, 64);
    expect(tester.getSize(find.byTooltip('Light')).width, 60);
    expect(tester.getSize(find.byTooltip('Light')).height, 56);
    expect(tester.takeException(), isNull);
  });
}
