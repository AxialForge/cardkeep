import 'package:axial_app_kit/axial_app_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// The palettes, families and theme pill now live in axial_app_kit; re-exported so existing imports keep working.
export 'package:axial_app_kit/axial_app_kit.dart' show AppPalette;

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
  static Color get strong => _p.strong;
  static Color get onStrong => _p.onStrong;
  static Color get action => _p.action;
  static Color get onAction => _p.onAction;
  static Color get onStrongMuted => _p.onStrong.withValues(alpha: 0.72);
  static Color get amberBg => _p.amberBg;
  static Color get amberFg => _p.amberFg;
  static Color get hotBg => _p.hotBg;
  static Color get hotFg => _p.hotFg;
  static Color get coldBg => _p.coldBg;
  static Color get coldFg => _p.coldFg;

  /// Status bar icons for screens on the page background.
  static SystemUiOverlayStyle get groundOverlay => _p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;

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
  final scheme = ColorScheme.fromSeed(seedColor: Tokens.brass, brightness: AppPalette.current.brightness).copyWith(
    primary: Tokens.strong,
    onPrimary: Tokens.onStrong,
    secondary: Tokens.action,
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
        backgroundColor: Tokens.action,
        foregroundColor: Tokens.onAction,
        minimumSize: const Size(48, 52),
        textStyle: AppText.button,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.radiusSm)),
      ),
    ),
    // Text buttons (Add phone, Set, Add note…) use the accent so they read in every palette.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Tokens.brassText, textStyle: AppText.button),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: Tokens.ink)),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: Tokens.action, linearTrackColor: Tokens.selected),
    popupMenuTheme: PopupMenuThemeData(color: Tokens.surface, textStyle: AppText.body),
    dialogTheme: DialogThemeData(backgroundColor: Tokens.surface),
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
      backgroundColor: Tokens.action,
      foregroundColor: Tokens.onAction,
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
      selectedColor: Tokens.action,
      side: BorderSide(color: Tokens.hairline),
      labelStyle: AppText.label,
      secondaryLabelStyle: AppText.label.copyWith(color: Tokens.onAction),
      checkmarkColor: Tokens.onAction,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Tokens.strong,
      contentTextStyle: AppText.body.copyWith(color: Tokens.onStrong),
      actionTextColor: Tokens.brass,
      behavior: SnackBarBehavior.floating,
    ),
    listTileTheme: ListTileThemeData(iconColor: Tokens.ink, minVerticalPadding: 10),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: Tokens.surface, showDragHandle: true),
  );
}
