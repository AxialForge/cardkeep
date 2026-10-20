import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';
import 'theme.dart';

class CardOrganizerApp extends StatefulWidget {
  final String initialLocation;
  const CardOrganizerApp({super.key, this.initialLocation = '/'});

  @override
  State<CardOrganizerApp> createState() => _CardOrganizerAppState();
}

class _CardOrganizerAppState extends State<CardOrganizerApp> {
  late final GoRouter _router = buildRouter(initialLocation: widget.initialLocation);

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'CardKeep',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        routerConfig: _router,
      );
}
