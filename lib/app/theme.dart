import 'package:flutter/material.dart';

/// Design tokens from the executive mockups (CLAUDE.md, Design rules).
class Tokens {
  static const ground = Color(0xFFF3F4F6);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF0E1A2B);
  static const ink2 = Color(0xFF4A5568);
  static const hairline = Color(0xFFE2E5EA);
  static const brass = Color(0xFFB08A4A);
  static const brassText = Color(0xFF7A5B22);
  static const amberBg = Color(0xFFFBF1DC);
  static const amberFg = Color(0xFF7A4E0B);
  static const hotBg = Color(0xFFF8E1DD);
  static const hotFg = Color(0xFF8C2F1F);
  static const coldBg = Color(0xFFE1EAF5);
  static const coldFg = Color(0xFF1F4A78);
  static const selected = Color(0xFFE6EBF2);

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
  static final display = _t(_display, 34, 600, Tokens.ink, height: 1.1);
  static final title = _t(_display, 26, 600, Tokens.ink, height: 1.15);
  static final heading = _t(_display, 20, 600, Tokens.ink);
  static final body = _t(_ui, 15, 400, Tokens.ink, height: 1.35);
  static final bodyStrong = _t(_ui, 15, 600, Tokens.ink);
  static final secondary = _t(_ui, 13.5, 400, Tokens.ink2, height: 1.3);
  static final label = _t(_ui, 12.5, 600, Tokens.ink2);
  static final overline = _t(_ui, 11.5, 700, Tokens.brassText, spacing: 1.1);
  static final button = _t(_ui, 15, 600, Tokens.ink);
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
    dividerTheme: const DividerThemeData(color: Tokens.hairline, thickness: 1, space: 1),
    drawerTheme: const DrawerThemeData(backgroundColor: Tokens.surface, width: 308),
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
        side: const BorderSide(color: Tokens.ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.radiusSm)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Tokens.ink,
      foregroundColor: Colors.white,
      extendedTextStyle: TextStyle(fontFamily: _ui, fontSize: 16, fontWeight: FontWeight.w600),
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
        borderSide: const BorderSide(color: Tokens.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusSm),
        borderSide: const BorderSide(color: Tokens.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusSm),
        borderSide: const BorderSide(color: Tokens.brass, width: 1.5),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Tokens.surface,
      selectedColor: Tokens.ink,
      side: const BorderSide(color: Tokens.hairline),
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
    listTileTheme: const ListTileThemeData(iconColor: Tokens.ink, minVerticalPadding: 10),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Tokens.surface, showDragHandle: true),
  );
}
