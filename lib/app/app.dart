import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers.dart';
import 'router.dart';
import 'theme.dart';

class CardOrganizerApp extends ConsumerStatefulWidget {
  final String initialLocation;
  const CardOrganizerApp({super.key, this.initialLocation = '/'});

  @override
  ConsumerState<CardOrganizerApp> createState() => _CardOrganizerAppState();
}

class _CardOrganizerAppState extends ConsumerState<CardOrganizerApp> {
  late final GoRouter _router = buildRouter(initialLocation: widget.initialLocation);

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  /// Tokens are read at build time, so a palette change rebuilds every element
  /// (the same walk hot reload does). Navigation state is kept.
  void _rebuildAll() {
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    (context as Element).visitChildren(mark);
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds when the phone switches between light and dark mode.
    final platform = MediaQuery.platformBrightnessOf(context);
    final choice = ref.watch(themeChoiceProvider).value ?? AppPalette.systemId;
    final palette = AppPalette.resolve(choice, platform);
    if (!identical(palette, AppPalette.current)) {
      AppPalette.current = palette;
      WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildAll());
    }
    return MaterialApp.router(
      title: 'CardKeep',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: _router,
    );
  }
}
