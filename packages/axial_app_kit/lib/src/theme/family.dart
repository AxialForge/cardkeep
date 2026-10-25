import 'package:flutter/material.dart';

import 'palette.dart';

/// A named look with a light and a dark palette. A family only pairs two
/// palettes for the theme picker; the palettes themselves live in palette.dart.
class ThemeFamily {
  const ThemeFamily(this.id, this.label, this.light, this.dark);

  final String id;
  final String label;
  final AppPalette light;
  final AppPalette dark;

  /// Warm orange: Light + Dark. Apps usually re-label this with their own name
  /// (CardKeep calls it "CardKeep"); the ids stay `classic`, `light`, `dark`.
  static const classic = ThemeFamily('classic', 'Classic', AppPalette.light, AppPalette.dark);

  /// Navy and brass: its light and dark palettes.
  static const navyBrass = ThemeFamily('executive', 'Navy and brass', AppPalette.executive, AppPalette.executiveDark);

  static const harbor = ThemeFamily('harbor', 'Harbor', AppPalette.harbor, AppPalette.harborDark);
  static const rosewater = ThemeFamily('rosewater', 'Rosewater', AppPalette.rosewater, AppPalette.rosewaterDark);
  static const sage = ThemeFamily('sage', 'Sage', AppPalette.sage, AppPalette.sageDark);
  static const lamplight = ThemeFamily('lamplight', 'Lamplight', AppPalette.lamplightDay, AppPalette.lamplight);

  /// Every family the kit ships, in the order the pills are listed.
  static const standard = [classic, navyBrass, harbor, rosewater, sage, lamplight];

  AppPalette forBrightness(Brightness b) => b == Brightness.dark ? dark : light;

  /// Picker bubbles: background, accent, secondary (ink).
  List<Color> bubbles(AppPalette p) => [p.ground, p.accent, p.ink];
}

/// The families one app offers, and which of them is the default. An app builds
/// its own catalog (re-labelled, reordered or trimmed) from [ThemeFamily.standard].
class ThemeCatalog {
  const ThemeCatalog(this.families, {ThemeFamily? defaultFamily}) : _default = defaultFamily;

  final List<ThemeFamily> families;
  final ThemeFamily? _default;

  /// The family a bare `system` choice means. The first family unless set.
  ThemeFamily get defaultFamily => _default ?? families.first;

  /// Everything the kit ships, with the kit's own default.
  static const standard = ThemeCatalog(ThemeFamily.standard);

  /// Unknown or unset ids fall back to the default family.
  ThemeFamily byId(String? id) => families.where((f) => f.id == id).firstOrNull ?? defaultFamily;

  ThemeFamily ofPalette(AppPalette p) =>
      families.where((f) => f.light.id == p.id || f.dark.id == p.id).firstOrNull ?? defaultFamily;
}

/// What the user picked: a family plus a mode. Saved as a single string, and
/// every id saved by older versions still means what it meant:
///   'system'             Light/Dark following the phone, default family
///   `system:<familyId>`  same, for another family, for example 'system:executive'
///   'light' 'dark' 'executive' 'executiveDark' ...   a fixed palette
class ThemeChoice {
  const ThemeChoice(this.family, this.mode, {this.catalog = ThemeCatalog.standard});

  final ThemeFamily family;
  final ThemeMode mode; // system, light or dark
  final ThemeCatalog catalog;

  static ThemeChoice parse(String? raw, {ThemeCatalog catalog = ThemeCatalog.standard}) {
    final v = raw ?? AppPalette.systemId;
    if (v == AppPalette.systemId) return ThemeChoice(catalog.defaultFamily, ThemeMode.system, catalog: catalog);
    const prefix = '${AppPalette.systemId}:';
    if (v.startsWith(prefix)) {
      return ThemeChoice(catalog.byId(v.substring(prefix.length)), ThemeMode.system, catalog: catalog);
    }
    final p = AppPalette.byId(v);
    return ThemeChoice(catalog.ofPalette(p), p.isDark ? ThemeMode.dark : ThemeMode.light, catalog: catalog);
  }

  /// The string to save in settings.
  String get id => switch (mode) {
    ThemeMode.system =>
      family == catalog.defaultFamily ? AppPalette.systemId : '${AppPalette.systemId}:${family.id}',
    ThemeMode.light => family.light.id,
    ThemeMode.dark => family.dark.id,
  };

  /// The palette to draw with, given the phone's current brightness.
  AppPalette palette(Brightness platform) => switch (mode) {
    ThemeMode.system => family.forBrightness(platform),
    ThemeMode.light => family.light,
    ThemeMode.dark => family.dark,
  };

  ThemeChoice withFamily(ThemeFamily f) => ThemeChoice(f, mode, catalog: catalog);
  ThemeChoice withMode(ThemeMode m) => ThemeChoice(family, m, catalog: catalog);
}
