import 'package:flutter/material.dart';

import '../../app/drawer.dart';
import '../../app/widgets.dart';

/// Drawer destinations that land in a later milestone (see docs/ROADMAP.md).
class ComingSoonScreen extends StatelessWidget {
  final Destination destination;
  const ComingSoonScreen({super.key, required this.destination});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(destination.label)),
    body: EmptyState(
      icon: destination.icon,
      title: '${destination.label} is on the way',
      message: 'This part of the app arrives in version ${destination.milestone}.',
    ),
  );
}
