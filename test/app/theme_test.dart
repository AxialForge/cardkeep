import 'package:card_organizer/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Match phone follows the platform brightness', () {
    expect(AppPalette.resolve(AppPalette.systemId, Brightness.light), AppPalette.light);
    expect(AppPalette.resolve(AppPalette.systemId, Brightness.dark), AppPalette.dark);
  });

  test('a fixed choice ignores the platform', () {
    expect(AppPalette.resolve('executiveDark', Brightness.light), AppPalette.executiveDark);
    expect(AppPalette.resolve('executive', Brightness.dark), AppPalette.executive);
  });

  test('old and unknown ids fall back to Light', () {
    expect(AppPalette.byId('medium'), AppPalette.light, reason: 'Medium removed in 0.3');
    expect(AppPalette.byId('cardkeep'), AppPalette.light);
    expect(AppPalette.byId('nope'), AppPalette.light);
    expect(AppPalette.byId(null), AppPalette.light);
  });

  test('every palette keeps body text readable (contrast >= 4.5:1)', () {
    double lum(Color c) => c.computeLuminance();
    double ratio(Color a, Color b) {
      final (x, y) = (lum(a), lum(b));
      return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
    }

    for (final p in AppPalette.all) {
      expect(ratio(p.ink, p.surface), greaterThanOrEqualTo(4.5), reason: '${p.id} ink/surface');
      expect(ratio(p.ink, p.ground), greaterThanOrEqualTo(4.5), reason: '${p.id} ink/ground');
      expect(ratio(p.ink2, p.surface), greaterThanOrEqualTo(4.5), reason: '${p.id} ink2/surface');
      expect(ratio(p.ink2, p.ground), greaterThanOrEqualTo(4.5), reason: '${p.id} ink2/ground');
      expect(ratio(p.onStrong, p.strong), greaterThanOrEqualTo(4.5), reason: '${p.id} header text');
      expect(ratio(p.accentText, p.ground), greaterThanOrEqualTo(4.5), reason: '${p.id} accent text/ground');
      expect(ratio(p.accentText, p.surface), greaterThanOrEqualTo(4.5), reason: '${p.id} accent text/surface');
      expect(ratio(p.amberFg, p.amberBg), greaterThanOrEqualTo(4.5), reason: '${p.id} amber pill');
      expect(ratio(p.hotFg, p.hotBg), greaterThanOrEqualTo(4.5), reason: '${p.id} hot pill');
      expect(ratio(p.coldFg, p.coldBg), greaterThanOrEqualTo(4.5), reason: '${p.id} cold pill');
    }
    // Button text on the primary colour: the four original palettes are left exactly as
    // they shipped (Dark's orange button is 3.9:1); the Pagemark looks must pass.
    for (final p in AppPalette.all.skip(4)) {
      expect(ratio(p.onAction, p.action), greaterThanOrEqualTo(4.5), reason: '${p.id} button text');
    }
  });

  test('every palette id is unique and dark palettes have a dark ground', () {
    final ids = AppPalette.all.map((p) => p.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final p in AppPalette.all.where((p) => p.isDark)) {
      expect(p.ground.computeLuminance(), lessThan(0.02), reason: '${p.id} is a true dark ground');
    }
    for (final p in AppPalette.all.where((p) => !p.isDark)) {
      expect(p.ground.computeLuminance(), greaterThan(0.85), reason: '${p.id} is a light ground');
    }
  });

  // The four palettes that shipped before the Pagemark looks. These values must never change.
  test('the original four palettes keep exactly their colours', () {
    const expected = <String, List<int>>{
      // ground, surface, ink, ink2, hairline, accent, accentText, selected, headerTint, strong, action
      'light': [
        0xFFFAFAF9,
        0xFFFFFFFF,
        0xFF1C1B19,
        0xFF5E5A54,
        0xFFE6E3DE,
        0xFFC4542D,
        0xFFA2421F,
        0xFFF4F0EA,
        0xFF3A3833,
        0xFF24231F,
        0xFFC4542D,
      ],
      'dark': [
        0xFF000000,
        0xFF151413,
        0xFFF1ECE3,
        0xFFABA59B,
        0xFF2B2926,
        0xFFE2703F,
        0xFFF08B5E,
        0xFF262421,
        0xFF34312D,
        0xFF1D1C1A,
        0xFFD25F33,
      ],
      'executive': [
        0xFFF3F4F6,
        0xFFFFFFFF,
        0xFF0E1A2B,
        0xFF4A5568,
        0xFFE2E5EA,
        0xFFB08A4A,
        0xFF7A5B22,
        0xFFE6EBF2,
        0xFF1C2A3E,
        0xFF0E1A2B,
        0xFF0E1A2B,
      ],
      'executiveDark': [
        0xFF08101C,
        0xFF111B2B,
        0xFFECEFF4,
        0xFFA3AEC0,
        0xFF23314A,
        0xFFC9A35E,
        0xFFD9B675,
        0xFF1A2740,
        0xFF22324C,
        0xFF0D1727,
        0xFFC9A35E,
      ],
    };
    for (final e in expected.entries) {
      final p = AppPalette.byId(e.key);
      expect(p.id, e.key);
      final got = [
        p.ground,
        p.surface,
        p.ink,
        p.ink2,
        p.hairline,
        p.accent,
        p.accentText,
        p.selected,
        p.headerTint,
        p.strong,
        p.action,
      ].map((c) => c.toARGB32()).toList();
      expect(got, e.value, reason: e.key);
    }
    expect(AppPalette.all.take(4).map((p) => p.id), ['light', 'dark', 'executive', 'executiveDark']);
  });
}
