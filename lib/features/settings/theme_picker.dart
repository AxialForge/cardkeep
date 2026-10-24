import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/theme_family.dart';
import '../../app/widgets.dart';
import '../../kit/theme_pill.dart';

/// The Match phone switch and one pill per look, with a light and a dark
/// version each. Used by Settings and by the tour's set-up page.
class ThemePicker extends ConsumerWidget {
  const ThemePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(settingsRepoProvider);
    final choice = ref.watch(themeChoiceProvider).value ?? AppPalette.systemId;
    final platform = MediaQuery.platformBrightnessOf(context);
    final theme = ThemeChoice.parse(choice);
    final shownBrightness = switch (theme.mode) {
      ThemeMode.system => platform,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.light => Brightness.light,
    };
    return Column(
      children: [
        Panel(
          padding: EdgeInsets.zero,
          child: SwitchListTile(
            value: theme.mode == ThemeMode.system,
            activeThumbColor: Tokens.brass,
            onChanged: (on) => settings.setTheme(
              theme
                  .withMode(on ? ThemeMode.system : (platform == Brightness.dark ? ThemeMode.dark : ThemeMode.light))
                  .id,
            ),
            title: Text('Match phone', style: AppText.body),
            subtitle: Text("Light or Dark, following your phone's setting", style: AppText.secondary),
          ),
        ),
        const SizedBox(height: 6),
        for (final f in ThemeFamily.all)
          ThemePill(
            name: f.label,
            lightColors: f.bubbles(f.light),
            darkColors: f.bubbles(f.dark),
            surface: Tokens.surface,
            hairline: Tokens.hairline,
            ink: Tokens.ink,
            accent: f.forBrightness(shownBrightness).accent,
            nameStyle: AppText.heading,
            selected: f == theme.family,
            pinned: f == theme.family && theme.mode != ThemeMode.system ? theme.mode : null,
            onSelectTheme: () => settings.setTheme(theme.withFamily(f).id),
            onSelectLight: () => settings.setTheme(ThemeChoice(f, ThemeMode.light).id),
            onSelectDark: () => settings.setTheme(ThemeChoice(f, ThemeMode.dark).id),
          ),
      ],
    );
  }
}
