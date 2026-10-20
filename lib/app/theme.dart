import 'package:flutter/material.dart';

/// A colour theme. Status colours (amber/hot/cold) stay the same in every palette.
class AppPalette {
  final String id;
  final String label;
  final Color ground; // page background
  final Color surface; // panels
  final Color ink; // text, primary buttons, dark headers
  final Color ink2; // secondary text
  final Color hairline;
  final Color accent; // highlights, brand detail
  final Color accentText; // accent used as text on light backgrounds (AA contrast)
  final Color selected; // selected rows, segmented background
  final Color headerTint; // avatar disc on the dark header

  const AppPalette({
    required this.id,
    required this.label,
    required this.ground,
    required this.surface,
    required this.ink,
    required this.ink2,
    required this.hairline,
    required this.accent,
    required this.accentText,
    required this.selected,
    required this.headerTint,
  });

  /// The executive mockups: navy and brass.
  static const executive = AppPalette(
    id: 'executive',
    label: 'Navy and brass',
    ground: Color(0xFFF3F4F6),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF0E1A2B),
    ink2: Color(0xFF4A5568),
    hairline: Color(0xFFE2E5EA),
    accent: Color(0xFFB08A4A),
    accentText: Color(0xFF7A5B22),
    selected: Color(0xFFE6EBF2),
    headerTint: Color(0xFF1C2A3E),
  );

  /// The CardKeep logo colours: orange on ivory with charcoal.
  static const cardkeep = AppPalette(
    id: 'cardkeep',
    label: 'CardKeep orange',
    ground: Color(0xFFF7F4ED),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF24231F),
    ink2: Color(0xFF5B574F),
    hairline: Color(0xFFE7E1D5),
    accent: Color(0xFFC4542D),
    accentText: Color(0xFFA2421F),
    selected: Color(0xFFF2EADF),
    headerTint: Color(0xFF3A3833),
  );

  static const all = [executive, cardkeep];

  static AppPalette byId(String? id) => all.where((p) => p.id == id).firstOrNull ?? executive;

  /// The palette the app is drawn with. Set by CardKeepApp before each build.
  static AppPalette current = executive;
}

/// Design tokens. Colours read the current palette, so they are getters, not consts.
class Tokens {
  static AppPalette get _p => AppPalette.current;
  static Color get ground => _p.ground;
  static Color get surface => _p.surface;
  static Color get ink => _p.ink;
  static Color get ink2 => _p.ink2;
  static Color get hairline => _p.hairline;
  static Color get brass => _p.accent;
  static Color get brassText => _p.accentText;
  static Color get selected => _p.selected;
  static Color get headerTint => _p.headerTint;

  static const amberBg = Color(0xFFFBF1DC);
  static const amberFg = Color(0xFF7A4E0B);
  static const hotBg = Color(0xFFF8E1DD);
  static const hotFg = Color(0xFF8C2F1F);
  static const coldBg = Color(0xFFE1EAF5);
  static const coldFg = Color(0xFF1F4A78);

  // CardKeep brand (logo package): orange mark on ivory.
  static const brandOrange = Color(0xFFC4542D);
  static const brandIvory = Color(0xFFF7F4ED);
  static const brandCharcoal = Color(0xFF24231F);

  static const radius = 18.0;
  static const radiusSm = 12.0;
  static const gutter = 16.0;
}

const _display = 'Newsreader';
const _ui = 'HankenGrotesk';

/// Variable fonts: weight comes from the wght axis, not fontWeight alone.
TextStyle _t(String family, double size, double weight, Color color, {double? height, double? spacing}) => TextStyle(
  fontFamily: family,
  fontSize: size,
  fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
  fontVariations: [FontVariation('wght', weight)],
  color: color,
  height: height,
  letterSpacing: spacing,
);

class AppText {
  static TextStyle get display => _t(_display, 34, 600, Tokens.ink, height: 1.1);
  static TextStyle get title => _t(_display, 26, 600, Tokens.ink, height: 1.15);
  static TextStyle get heading => _t(_display, 20, 600, Tokens.ink);
  static TextStyle get body => _t(_ui, 15, 400, Tokens.ink, height: 1.35);
  static TextStyle get bodyStrong => _t(_ui, 15, 600, Tokens.ink);
  static TextStyle get secondary => _t(_ui, 13.5, 400, Tokens.ink2, height: 1.3);
  static TextStyle get label => _t(_ui, 12.5, 600, Tokens.ink2);
  static TextStyle get overline => _t(_ui, 11.5, 700, Tokens.brassText, spacing: 1.1);
  static TextStyle get button => _t(_ui, 15, 600, Tokens.ink);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: Tokens.ink, brightness: Brightness.light).copyWith(
    primary: Tokens.ink,
    onPrimary: Colors.white,
    secondary: Tokens.brass,
    onSecondary: Colors.white,
    surface: Tokens.surface,
    onSurface: Tokens.ink,
    onSurfaceVariant: Tokens.ink2,
    outline: Tokens.hairline,
    outlineVariant: Tokens.hairline,
    error: Tokens.hotFg,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: _ui);
  return base.copyWith(
    scaffoldBackgroundColor: Tokens.ground,
    textTheme: base.textTheme.copyWith(
      displaySmall: AppText.display,
      headlineSmall: AppText.title,
      titleLarge: AppText.heading,
      titleMedium: AppText.bodyStrong,
      bodyLarge: AppText.body,
      bodyMedium: AppText.body,
      bodySmall: AppText.secondary,
      labelLarge: AppText.button,
      labelMedium: AppText.label,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Tokens.ground,
      foregroundColor: Tokens.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: AppText.heading,
    ),
    dividerTheme: DividerThemeData(color: Tokens.hairline, thickness: 1, space: 1),
    drawerTheme: DrawerThemeData(backgroundColor: Tokens.surface, width: 308),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Tokens.ink,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 52),
        textStyle: AppText.button,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.radiusSm)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Tokens.ink,
        minimumSize: const Size(48, 52),
        textStyle: AppText.button,
        side: BorderSide(color: Tokens.ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.radiusSm)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Tokens.ink,
      foregroundColor: Colors.white,
      extendedTextStyle: const TextStyle(fontFamily: _ui, fontSize: 16, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Tokens.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: AppText.secondary,
      floatingLabelStyle: AppText.label,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusSm),
        borderSide: BorderSide(color: Tokens.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusSm),
        borderSide: BorderSide(color: Tokens.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusSm),
        borderSide: BorderSide(color: Tokens.brass, width: 1.5),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Tokens.surface,
      selectedColor: Tokens.ink,
      side: BorderSide(color: Tokens.hairline),
      labelStyle: AppText.label,
      secondaryLabelStyle: AppText.label.copyWith(color: Colors.white),
      checkmarkColor: Colors.white,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Tokens.ink,
      contentTextStyle: AppText.body.copyWith(color: Colors.white),
      actionTextColor: Tokens.brass,
      behavior: SnackBarBehavior.floating,
    ),
    listTileTheme: ListTileThemeData(iconColor: Tokens.ink, minVerticalPadding: 10),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: Tokens.surface, showDragHandle: true),
  );
}
