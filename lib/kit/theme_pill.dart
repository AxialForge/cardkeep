import 'package:flutter/material.dart';

/// Theme picker pill ("Option B" in the UI Kit Guide).
///
/// One pill per named theme: the name on the left, then a light cluster and a
/// dark cluster of three overlapping bubbles (background, accent, secondary).
///  * Tap the pill: select the theme, keep the current light/dark mode.
///  * Tap a cluster: select the theme and pin that mode.
///  * Long-press a cluster: tooltip "Light" or "Dark".
///
/// This widget knows nothing about any app's palette classes. The caller passes
/// plain colours and callbacks, so the same file works in every app.
class ThemePill extends StatelessWidget {
  const ThemePill({
    super.key,
    required this.name,
    required this.lightColors,
    required this.darkColors,
    required this.surface,
    required this.hairline,
    required this.ink,
    required this.accent,
    required this.selected,
    required this.pinned,
    required this.onSelectTheme,
    required this.onSelectLight,
    required this.onSelectDark,
    this.nameStyle,
  });

  /// Theme name, for example "Navy and brass".
  final String name;

  /// Three colours each: background, accent, secondary.
  final List<Color> lightColors;
  final List<Color> darkColors;

  /// Colours of the page the pill sits on: pill fill, 1 dp border, text, bubble outline.
  final Color surface;
  final Color hairline;
  final Color ink;

  /// Selection border and mode ring.
  final Color accent;

  /// True when this is the active theme.
  final bool selected;

  /// [ThemeMode.light] or [ThemeMode.dark] when that mode is pinned for the
  /// selected theme; null when following the system (no ring is drawn).
  final ThemeMode? pinned;

  final VoidCallback onSelectTheme;
  final VoidCallback onSelectLight;
  final VoidCallback onSelectDark;

  /// Optional font for the name. Size and colour are set here (20 sp, 18 sp on phones under 340 dp).
  final TextStyle? nameStyle;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 340;
    final style = (nameStyle ?? const TextStyle(fontWeight: FontWeight.w500)).copyWith(
      fontSize: narrow ? 18 : 20,
      color: ink,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        label: name,
        child: Material(
          color: surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: selected ? accent : hairline, width: selected ? 2 : 1),
          ),
          child: InkWell(
            onTap: onSelectTheme,
            splashColor: accent.withAlpha(41),
            highlightColor: accent.withAlpha(20),
            child: SizedBox(
              height: 64,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: ExcludeSemantics(
                        child: Text(name, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    _Zone(
                      name: name,
                      label: 'Light',
                      colors: lightColors,
                      pinned: pinned == ThemeMode.light,
                      accent: accent,
                      outline: ink,
                      onTap: onSelectLight,
                    ),
                    SizedBox(width: narrow ? 4 : 8),
                    _Zone(
                      name: name,
                      label: 'Dark',
                      colors: darkColors,
                      pinned: pinned == ThemeMode.dark,
                      accent: accent,
                      outline: ink,
                      onTap: onSelectDark,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One tap zone: 60 x 56 dp, 12 dp corner, holding a cluster of three bubbles.
class _Zone extends StatelessWidget {
  const _Zone({
    required this.name,
    required this.label,
    required this.colors,
    required this.pinned,
    required this.accent,
    required this.outline,
    required this.onTap,
  });

  final String name;
  final String label;
  final List<Color> colors;
  final bool pinned;
  final Color accent;
  final Color outline;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        container: true,
        button: true,
        selected: pinned,
        label: '$name, ${label.toLowerCase()}',
        excludeSemantics: true,
        onTap: onTap,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            splashColor: accent.withAlpha(51),
            highlightColor: accent.withAlpha(41),
            child: Container(
              width: 60,
              height: 56,
              alignment: Alignment.center,
              decoration: pinned
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: accent, width: 2),
                    )
                  : null,
              // 24 dp bubbles, 14 dp step (10 dp overlap): 24 + 2 x 14 = 52 dp wide.
              child: SizedBox(
                width: 52,
                height: 24,
                child: Stack(
                  children: [
                    for (final (i, c) in colors.take(3).indexed)
                      Positioned(
                        left: i * 14.0,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(color: outline.withAlpha(77), width: 1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
