import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/db/pre_upgrade_copy.dart';

/// Shown instead of the app when the library cannot be opened after an update.
/// Nothing has been deleted: the library file is where it was, and a copy made
/// just before the update (see pre_upgrade_copy.dart) can be put back.
class UpgradeFailedApp extends StatefulWidget {
  final Directory docs;
  final Object error;
  const UpgradeFailedApp({super.key, required this.docs, required this.error});

  @override
  State<UpgradeFailedApp> createState() => _UpgradeFailedAppState();
}

class _UpgradeFailedAppState extends State<UpgradeFailedApp> {
  bool _busy = false;

  Future<void> _goBack() async {
    final c = listUpgradeCopies(widget.docs).firstOrNull;
    if (c == null) return;
    setState(() => _busy = true);
    await stageUpgradeCopyOf(widget.docs, c);
    // The swap happens at the next start, before the library opens.
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final copy = listUpgradeCopies(widget.docs).firstOrNull;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFFC4562E), useMaterial3: true),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CardKeep could not open your library',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Nothing has been deleted. Your contacts and card photos are still on this phone, but the update '
                  'could not read them.',
                ),
                const SizedBox(height: 12),
                if (copy != null)
                  const Text('CardKeep kept a copy of your library from just before the update. You can put it back.')
                else
                  const Text(
                    'Restart CardKeep. If this stays, restore a backup from Export and backup, or install the '
                    'earlier version again and report the problem on GitHub.',
                  ),
                const SizedBox(height: 24),
                if (copy != null)
                  FilledButton(
                    onPressed: _busy ? null : _goBack,
                    child: const Text('Go back to the copy from before the update'),
                  ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () => SystemNavigator.pop(), child: const Text('Close CardKeep')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
