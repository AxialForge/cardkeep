import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A colour theme. Status colours (amber/hot/cold) stay the same in every palette.
class AppPalette {
  final String id;
  final String label;
  final Color ground; // page background
  final Color surface; // panels
  final Color ink; // text
  final Color ink2; // secondary text
  final Color hairline;
  final Color accent; // highlights, brand detail
  final Color accentText; // accent used as text on the page (AA contrast)
  final Color selected; // selected rows, segmented background
  final Color headerTint; // avatar disc on the dark header
  final Brightness brightness;
  final Color strong; // dark surfaces: headers, banners
  final Color onStrong; // text and icons on [strong]
  final Color action; // primary controls: buttons, FAB, selected chips, Call/Email
  final Color onAction;
  final Color amberBg, amberFg, hotBg, hotFg, coldBg, coldFg; // status pills

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
    required this.strong,
    this.action = const Color(0xFFC4542D),
    this.onAction = const Color(0xFFFFFFFF),
    this.brightness = Brightness.light,
    this.onStrong = const Color(0xFFFFFFFF),
    this.amberBg = const Color(0xFFFBF1DC),
    this.amberFg = const Color(0xFF7A4E0B),
    this.hotBg = const Color(0xFFF8E1DD),
    this.hotFg = const Color(0xFF8C2F1F),
    this.coldBg = const Color(0xFFE1EAF5),
    this.coldFg = const Color(0xFF1F4A78),
  });

  /// Light: white page, charcoal headers, CardKeep orange controls. The default.
  static const light = AppPalette(
    id: 'light',
    label: 'Light',
    ground: Color(0xFFFAFAF9),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF1C1B19),
    ink2: Color(0xFF5E5A54),
    hairline: Color(0xFFE6E3DE),
    accent: Color(0xFFC4542D),
    accentText: Color(0xFFA2421F),
    selected: Color(0xFFF4F0EA),
    headerTint: Color(0xFF3A3833),
    strong: Color(0xFF24231F),
  );

  /// Dark: black page, near-black panels, warm off-white text, brighter orange.
  static const dark = AppPalette(
    id: 'dark',
    label: 'Dark',
    brightness: Brightness.dark,
    ground: Color(0xFF000000),
    surface: Color(0xFF151413),
    ink: Color(0xFFF1ECE3),
    ink2: Color(0xFFABA59B),
    hairline: Color(0xFF2B2926),
    accent: Color(0xFFE2703F),
    accentText: Color(0xFFF08B5E),
    selected: Color(0xFF262421),
    headerTint: Color(0xFF34312D),
    strong: Color(0xFF1D1C1A),
    onStrong: Color(0xFFF7F4ED),
    action: Color(0xFFD25F33),
    amberBg: Color(0xFF3A2E15),
    amberFg: Color(0xFFF2C978),
    hotBg: Color(0xFF45221B),
    hotFg: Color(0xFFF4A390),
    coldBg: Color(0xFF1C2B3D),
    coldFg: Color(0xFF9EC3EC),
  );

  /// The original executive mockups: navy and brass. Kept as an extra option.
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
    strong: Color(0xFF0E1A2B),
    action: Color(0xFF0E1A2B),
  );

  /// Navy and brass, dark: deep navy page, brass controls.
  static const executiveDark = AppPalette(
    id: 'executiveDark',
    label: 'Navy and brass dark',
    brightness: Brightness.dark,
    ground: Color(0xFF08101C),
    surface: Color(0xFF111B2B),
    ink: Color(0xFFECEFF4),
    ink2: Color(0xFFA3AEC0),
    hairline: Color(0xFF23314A),
    accent: Color(0xFFC9A35E),
    accentText: Color(0xFFD9B675),
    selected: Color(0xFF1A2740),
    headerTint: Color(0xFF22324C),
    strong: Color(0xFF0D1727),
    onStrong: Color(0xFFF2EEE4),
    action: Color(0xFFC9A35E),
    onAction: Color(0xFF0E1A2B),
    amberBg: Color(0xFF3A2E15),
    amberFg: Color(0xFFF2C978),
    hotBg: Color(0xFF45221B),
    hotFg: Color(0xFFF4A390),
    coldBg: Color(0xFF1C2B3D),
    coldFg: Color(0xFF9EC3EC),
  );

  // ---- Pagemark looks (0.7.3). Each is a light and a dark palette tuned by hand from the
  // Pagemark seed colour: every text role is at least 4.5:1 on its page, dark ones sit on a
  // true dark ground. Status pills (amber/hot/cold) follow the CardKeep dark set.

  /// Harbor: cool slate blue on a pale grey-blue page.
  static const harbor = AppPalette(
    id: 'harbor',
    label: 'Harbor',
    ground: Color(0xFFF4F6F9),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF111B27),
    ink2: Color(0xFF4A5668),
    hairline: Color(0xFFDFE5EC),
    accent: Color(0xFF2F5D8A),
    accentText: Color(0xFF244B72),
    selected: Color(0xFFE5ECF4),
    headerTint: Color(0xFF2A4767),
    strong: Color(0xFF1B3552),
    action: Color(0xFF2F5D8A),
  );

  /// Midnight Ink: Harbor in the dark.
  static const harborDark = AppPalette(
    id: 'harborDark',
    label: 'Midnight Ink',
    brightness: Brightness.dark,
    ground: Color(0xFF070C14),
    surface: Color(0xFF111924),
    ink: Color(0xFFE9EEF5),
    ink2: Color(0xFFA2AFC0),
    hairline: Color(0xFF223046),
    accent: Color(0xFF4F86C0),
    accentText: Color(0xFF7FAEE0),
    selected: Color(0xFF19263A),
    headerTint: Color(0xFF21344E),
    strong: Color(0xFF0D1522),
    onStrong: Color(0xFFF2F5FA),
    action: Color(0xFF3B6EA5),
    amberBg: Color(0xFF3A2E15),
    amberFg: Color(0xFFF2C978),
    hotBg: Color(0xFF45221B),
    hotFg: Color(0xFFF4A390),
    coldBg: Color(0xFF1C2B3D),
    coldFg: Color(0xFF9EC3EC),
  );

  /// Rosewater: dusty rose on a blush page.
  static const rosewater = AppPalette(
    id: 'rosewater',
    label: 'Rosewater',
    ground: Color(0xFFFBF6F7),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF24161C),
    ink2: Color(0xFF6A5159),
    hairline: Color(0xFFEEDFE3),
    accent: Color(0xFFC2557A),
    accentText: Color(0xFFA03A5E),
    selected: Color(0xFFF7E9ED),
    headerTint: Color(0xFF4A2A37),
    strong: Color(0xFF3A1F2A),
    action: Color(0xFFB8466C),
  );

  /// Plum Velvet: Rosewater in the dark.
  static const rosewaterDark = AppPalette(
    id: 'rosewaterDark',
    label: 'Plum Velvet',
    brightness: Brightness.dark,
    ground: Color(0xFF0E080C),
    surface: Color(0xFF1A1117),
    ink: Color(0xFFF3E9EE),
    ink2: Color(0xFFB8A3AD),
    hairline: Color(0xFF33222B),
    accent: Color(0xFFC467A0),
    accentText: Color(0xFFE08ABD),
    selected: Color(0xFF291A22),
    headerTint: Color(0xFF3A2431),
    strong: Color(0xFF190F15),
    onStrong: Color(0xFFF8EFF3),
    action: Color(0xFFA44A82),
    amberBg: Color(0xFF3A2E15),
    amberFg: Color(0xFFF2C978),
    hotBg: Color(0xFF45221B),
    hotFg: Color(0xFFF4A390),
    coldBg: Color(0xFF1C2B3D),
    coldFg: Color(0xFF9EC3EC),
  );

  /// Sage: calm green on a pale green-grey page.
  static const sage = AppPalette(
    id: 'sage',
    label: 'Sage',
    ground: Color(0xFFF6F8F5),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF15201A),
    ink2: Color(0xFF52625A),
    hairline: Color(0xFFE0E7DF),
    accent: Color(0xFF4F7A5A),
    accentText: Color(0xFF3A6145),
    selected: Color(0xFFE8EFE7),
    headerTint: Color(0xFF2C4434),
    strong: Color(0xFF213529),
    action: Color(0xFF3F6A4B),
  );

  /// Sage Night: Sage in the dark.
  static const sageDark = AppPalette(
    id: 'sageDark',
    label: 'Sage Night',
    brightness: Brightness.dark,
    ground: Color(0xFF080D09),
    surface: Color(0xFF111A14),
    ink: Color(0xFFE8F0E9),
    ink2: Color(0xFFA3B3A7),
    hairline: Color(0xFF223127),
    accent: Color(0xFF6A9D78),
    accentText: Color(0xFF8FC09C),
    selected: Color(0xFF19261D),
    headerTint: Color(0xFF22362A),
    strong: Color(0xFF0D1610),
    onStrong: Color(0xFFF1F6F2),
    action: Color(0xFF4F7A5A),
    amberBg: Color(0xFF3A2E15),
    amberFg: Color(0xFFF2C978),
    hotBg: Color(0xFF45221B),
    hotFg: Color(0xFFF4A390),
    coldBg: Color(0xFF1C2B3D),
    coldFg: Color(0xFF9EC3EC),
  );

  /// Lamplight Day: warm gold on a cream page.
  static const lamplightDay = AppPalette(
    id: 'lamplightDay',
    label: 'Lamplight Day',
    ground: Color(0xFFFBF7EE),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF241A0B),
    ink2: Color(0xFF6A5A3E),
    hairline: Color(0xFFEDE3CF),
    accent: Color(0xFFC4902F),
    accentText: Color(0xFF8A5F0F),
    selected: Color(0xFFF5ECD6),
    headerTint: Color(0xFF4A3716),
    strong: Color(0xFF33260E),
    action: Color(0xFF8F6410),
  );

  /// Lamplight: gold on warm near-black, like a reading lamp.
  static const lamplight = AppPalette(
    id: 'lamplight',
    label: 'Lamplight',
    brightness: Brightness.dark,
    ground: Color(0xFF0C0904),
    surface: Color(0xFF17120A),
    ink: Color(0xFFF3EBDA),
    ink2: Color(0xFFB5A78B),
    hairline: Color(0xFF2E2616),
    accent: Color(0xFFD9A441),
    accentText: Color(0xFFE8B95E),
    selected: Color(0xFF241C0E),
    headerTint: Color(0xFF3A2D14),
    strong: Color(0xFF130F07),
    onStrong: Color(0xFFF8F2E4),
    action: Color(0xFFC4902F),
    onAction: Color(0xFF1C1406),
    amberBg: Color(0xFF3A2E15),
    amberFg: Color(0xFFF2C978),
    hotBg: Color(0xFF45221B),
    hotFg: Color(0xFFF4A390),
    coldBg: Color(0xFF1C2B3D),
    coldFg: Color(0xFF9EC3EC),
  );

  static const all = [
    light,
    dark,
    executive,
    executiveDark,
    harbor,
    harborDark,
    rosewater,
    rosewaterDark,
    sage,
    sageDark,
    lamplightDay,
    lamplight,
  ];

  /// Theme choice that follows the phone: Light in light mode, Dark in dark mode.
  static const systemId = 'system';

  /// The palette for a saved choice and the phone's current brightness.
  static AppPalette resolve(String choice, Brightness platform) =>
      choice == systemId ? (platform == Brightness.dark ? dark : light) : byId(choice);

  /// Unknown or unset ids fall back to Light (the default). 'cardkeep' was the
  /// first orange palette's id; 'medium' was removed in 0.3 (too close to Light).
  static AppPalette byId(String? id) => all.where((p) => p.id == id).firstOrNull ?? light;

  /// The palette the app is drawn with. Set by CardOrganizerApp before each build.
  static AppPalette current = light;

  bool get isDark => brightness == Brightness.dark;
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
