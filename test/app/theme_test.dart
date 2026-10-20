import 'package:card_organizer/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Match phone follows the platform brightness', () {
    expect(AppPalette.resolve(AppPalette.systemId, Brightness.light), AppPalette.light);
    expect(AppPalette.resolve(AppPalette.systemId, Brightness.dark), AppPalette.dark);
  });

  test('a fixed choice ignores the platform', () {
    expect(AppPalette.resolve('medium', Brightness.dark), AppPalette.medium);
    expect(AppPalette.resolve('executive', Brightness.dark), AppPalette.executive);
  });

  test('old and unknown ids fall back to Light', () {
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
      expect(ratio(p.ink2, p.surface), greaterThanOrEqualTo(4.5), reason: '${p.id} ink2/surface');
      expect(ratio(p.onStrong, p.strong), greaterThanOrEqualTo(4.5), reason: '${p.id} header text');
      expect(ratio(p.accentText, p.ground), greaterThanOrEqualTo(4.5), reason: '${p.id} accent text');
    }
  });
}
