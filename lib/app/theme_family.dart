import 'package:flutter/material.dart';

import 'theme.dart';

/// A named look with a light and a dark palette. The palettes themselves stay in
/// theme.dart, unchanged: a family only pairs them for the theme picker.
class ThemeFamily {
  const ThemeFamily(this.id, this.label, this.light, this.dark);

  final String id;
  final String label;
  final AppPalette light;
  final AppPalette dark;

  /// CardKeep orange: Light + Dark.
  static const classic = ThemeFamily('classic', 'CardKeep', AppPalette.light, AppPalette.dark);

  /// Navy and brass: its light and dark palettes.
  static const navyBrass = ThemeFamily('executive', 'Navy and brass', AppPalette.executive, AppPalette.executiveDark);

  /// The Pagemark looks: Harbor and Midnight Ink, Rosewater and Plum Velvet,
  /// Sage and Sage Night, Lamplight Day and Lamplight. Listed after the two
  /// CardKeep looks so those stay first.
  static const harbor = ThemeFamily('harbor', 'Harbor', AppPalette.harbor, AppPalette.harborDark);
  static const rosewater = ThemeFamily('rosewater', 'Rosewater', AppPalette.rosewater, AppPalette.rosewaterDark);
  static const sage = ThemeFamily('sage', 'Sage', AppPalette.sage, AppPalette.sageDark);
  static const lamplight = ThemeFamily('lamplight', 'Lamplight', AppPalette.lamplightDay, AppPalette.lamplight);

  static const all = [classic, navyBrass, harbor, rosewater, sage, lamplight];

  static ThemeFamily byId(String? id) => all.where((f) => f.id == id).firstOrNull ?? classic;

  static ThemeFamily ofPalette(AppPalette p) =>
      all.where((f) => f.light.id == p.id || f.dark.id == p.id).firstOrNull ?? classic;

  AppPalette forBrightness(Brightness b) => b == Brightness.dark ? dark : light;

  /// Picker bubbles: background, accent, secondary (ink).
  List<Color> bubbles(AppPalette p) => [p.ground, p.accent, p.ink];
}

/// What the user picked: a family plus a mode. Saved as a single string so the
/// existing settings row keeps working, and every id saved by older versions
/// still means what it meant:
///   'system'             Light/Dark following the phone, CardKeep family (the old default)
///   `system:<familyId>`  same, for another family, for example 'system:executive'
///   'light' 'dark' 'executive' 'executiveDark'   a fixed palette (old ids)
class ThemeChoice {
  const ThemeChoice(this.family, this.mode);

  final ThemeFamily family;
  final ThemeMode mode; // system, light or dark

  static ThemeChoice parse(String? raw) {
    final v = raw ?? AppPalette.systemId;
    if (v == AppPalette.systemId) return const ThemeChoice(ThemeFamily.classic, ThemeMode.system);
    const prefix = '${AppPalette.systemId}:';
    if (v.startsWith(prefix)) {
      return ThemeChoice(ThemeFamily.byId(v.substring(prefix.length)), ThemeMode.system);
    }
    final p = AppPalette.byId(v);
    return ThemeChoice(ThemeFamily.ofPalette(p), p.isDark ? ThemeMode.dark : ThemeMode.light);
  }

  /// The string to save with SettingsRepository.setTheme.
  String get id => switch (mode) {
    ThemeMode.system => family == ThemeFamily.classic ? AppPalette.systemId : '${AppPalette.systemId}:${family.id}',
    ThemeMode.light => family.light.id,
    ThemeMode.dark => family.dark.id,
  };

  /// The palette to draw with, given the phone's current brightness.
  AppPalette palette(Brightness platform) => switch (mode) {
    ThemeMode.system => family.forBrightness(platform),
    ThemeMode.light => family.light,
    ThemeMode.dark => family.dark,
  };

  ThemeChoice withFamily(ThemeFamily f) => ThemeChoice(f, mode);
  ThemeChoice withMode(ThemeMode m) => ThemeChoice(family, m);
}
