import 'package:card_organizer/app/theme.dart';
import 'package:card_organizer/app/theme_family.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every id saved by older versions still resolves to the same palette', () {
    expect(ThemeChoice.parse('system').palette(Brightness.light), AppPalette.light);
    expect(ThemeChoice.parse('system').palette(Brightness.dark), AppPalette.dark);
    expect(ThemeChoice.parse('light').palette(Brightness.dark), AppPalette.light);
    expect(ThemeChoice.parse('dark').palette(Brightness.light), AppPalette.dark);
    expect(ThemeChoice.parse('executive').palette(Brightness.dark), AppPalette.executive);
    expect(ThemeChoice.parse('executiveDark').palette(Brightness.light), AppPalette.executiveDark);
    expect(ThemeChoice.parse(null).palette(Brightness.light), AppPalette.light);
    expect(ThemeChoice.parse('medium').palette(Brightness.light), AppPalette.light);
  });

  test('follow system works for every family', () {
    final c = ThemeChoice.parse('system:executive');
    expect(c.family, ThemeFamily.navyBrass);
    expect(c.mode, ThemeMode.system);
    expect(c.palette(Brightness.light), AppPalette.executive);
    expect(c.palette(Brightness.dark), AppPalette.executiveDark);
  });

  test('ids round-trip', () {
    for (final f in ThemeFamily.all) {
      for (final m in ThemeMode.values) {
        final c = ThemeChoice(f, m);
        final back = ThemeChoice.parse(c.id);
        expect(back.family, f, reason: c.id);
        expect(back.mode, m, reason: c.id);
      }
    }
  });

  test('the old default id is unchanged', () {
    expect(const ThemeChoice(ThemeFamily.classic, ThemeMode.system).id, AppPalette.systemId);
  });

  test('switching family keeps the mode', () {
    final c = ThemeChoice.parse('dark').withFamily(ThemeFamily.navyBrass);
    expect(c.id, 'executiveDark');
    final s = ThemeChoice.parse('system').withFamily(ThemeFamily.navyBrass);
    expect(s.id, 'system:executive');
  });

  test('the pills are listed CardKeep, Navy and brass, then the Pagemark looks', () {
    expect(ThemeFamily.all.map((f) => f.label), [
      'CardKeep',
      'Navy and brass',
      'Harbor',
      'Rosewater',
      'Sage',
      'Lamplight',
    ]);
    expect(ThemeFamily.all.first.light.id, 'light');
    expect(ThemeFamily.all.first.dark.id, 'dark');
  });

  test('the Pagemark looks pair light and dark, and follow the phone', () {
    final pairs = {
      'harbor': ('harbor', 'harborDark'),
      'rosewater': ('rosewater', 'rosewaterDark'),
      'sage': ('sage', 'sageDark'),
      'lamplight': ('lamplightDay', 'lamplight'),
    };
    for (final e in pairs.entries) {
      final f = ThemeFamily.byId(e.key);
      expect((f.light.id, f.dark.id), e.value, reason: e.key);
      expect(f.light.isDark, isFalse);
      expect(f.dark.isDark, isTrue);
      final follow = ThemeChoice.parse('system:${e.key}');
      expect(follow.family, f);
      expect(follow.palette(Brightness.light).id, e.value.$1);
      expect(follow.palette(Brightness.dark).id, e.value.$2);
      expect(ThemeChoice.parse(e.value.$2).id, e.value.$2, reason: 'a saved palette id keeps its meaning');
    }
  });

  test('all palettes are reachable from a family', () {
    final ids = {
      for (final f in ThemeFamily.all) ...[f.light.id, f.dark.id],
    };
    expect(ids, AppPalette.all.map((p) => p.id).toSet());
  });
}
