import 'package:axial_app_kit/axial_app_kit.dart';
import 'package:card_organizer/app/theme_family.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ThemeChoice _parse(String? raw) => ThemeChoice.parse(raw, catalog: cardkeepThemes);

void main() {
  test('every id saved by older versions still resolves to the same palette', () {
    expect(_parse('system').palette(Brightness.light), AppPalette.light);
    expect(_parse('system').palette(Brightness.dark), AppPalette.dark);
    expect(_parse('light').palette(Brightness.dark), AppPalette.light);
    expect(_parse('dark').palette(Brightness.light), AppPalette.dark);
    expect(_parse('executive').palette(Brightness.dark), AppPalette.executive);
    expect(_parse('executiveDark').palette(Brightness.light), AppPalette.executiveDark);
    expect(_parse(null).palette(Brightness.light), AppPalette.light);
    expect(_parse('medium').palette(Brightness.light), AppPalette.light);
  });

  test('follow system works for every family', () {
    final c = _parse('system:executive');
    expect(c.family, ThemeFamily.navyBrass);
    expect(c.mode, ThemeMode.system);
    expect(c.palette(Brightness.light), AppPalette.executive);
    expect(c.palette(Brightness.dark), AppPalette.executiveDark);
  });

  test('ids round-trip', () {
    for (final f in cardkeepThemes.families) {
      for (final m in ThemeMode.values) {
        final c = ThemeChoice(f, m, catalog: cardkeepThemes);
        final back = _parse(c.id);
        expect(back.family, f, reason: c.id);
        expect(back.mode, m, reason: c.id);
      }
    }
  });

  test('the old default id is unchanged', () {
    expect(ThemeChoice(cardkeepThemes.families.first, ThemeMode.system, catalog: cardkeepThemes).id, AppPalette.systemId);
  });

  test('switching family keeps the mode', () {
    final c = _parse('dark').withFamily(ThemeFamily.navyBrass);
    expect(c.id, 'executiveDark');
    final s = _parse('system').withFamily(ThemeFamily.navyBrass);
    expect(s.id, 'system:executive');
  });

  test('the pills are listed CardKeep, Navy and brass, then the Pagemark looks', () {
    expect(cardkeepThemes.families.map((f) => f.label), [
      'CardKeep',
      'Navy and brass',
      'Harbor',
      'Rosewater',
      'Sage',
      'Lamplight',
    ]);
    expect(cardkeepThemes.families.first.light.id, 'light');
    expect(cardkeepThemes.families.first.dark.id, 'dark');
  });

  test('the Pagemark looks pair light and dark, and follow the phone', () {
    final pairs = {
      'harbor': ('harbor', 'harborDark'),
      'rosewater': ('rosewater', 'rosewaterDark'),
      'sage': ('sage', 'sageDark'),
      'lamplight': ('lamplightDay', 'lamplight'),
    };
    for (final e in pairs.entries) {
      final f = cardkeepThemes.byId(e.key);
      expect((f.light.id, f.dark.id), e.value, reason: e.key);
      expect(f.light.isDark, isFalse);
      expect(f.dark.isDark, isTrue);
      final follow = _parse('system:${e.key}');
      expect(follow.family, f);
      expect(follow.palette(Brightness.light).id, e.value.$1);
      expect(follow.palette(Brightness.dark).id, e.value.$2);
      expect(_parse(e.value.$2).id, e.value.$2, reason: 'a saved palette id keeps its meaning');
    }
  });

  test('all palettes are reachable from a family', () {
    final ids = {
      for (final f in cardkeepThemes.families) ...[f.light.id, f.dark.id],
    };
    expect(ids, AppPalette.all.map((p) => p.id).toSet());
  });
}
