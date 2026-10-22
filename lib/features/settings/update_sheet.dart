import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/update/updater.dart';

/// Checks GitHub Releases, then shows what's new and installs the update.
Future<void> showUpdateSheet(BuildContext context) =>
    showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const _UpdateSheet());

class _UpdateSheet extends StatefulWidget {
  const _UpdateSheet();
  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  UpdateInfo? _info;
  String? _error;
  double? _progress;
  File? _apk;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _error = null);
    try {
      final i = await Updater.check();
      if (mounted) setState(() => _info = i);
    } on UpdateException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _install() async {
    setState(() {
      _error = null;
      _progress = 0;
    });
    try {
      _apk ??= await Updater.download(_info!, (p) => mounted ? setState(() => _progress = p) : null);
      if (mounted) setState(() => _progress = null);
      await Updater.install(_apk!);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is UpdateException ? e.message : 'The update did not work. Please try again.';
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = _info;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Updates', style: AppText.heading),
              const SizedBox(height: 4),
              Text('Checks github.com/${Updater.repo}. Nothing else is sent.', style: AppText.secondary),
              const SizedBox(height: 16),
              if (i == null && _error == null) const Center(child: CircularProgressIndicator()),
              if (i != null && !i.available)
                Text('CardKeep ${i.current} is the latest version.', style: AppText.bodyStrong),
              if (i != null && i.available) ...[
                Text('CardKeep ${i.latest} is available (you have ${i.current}).', style: AppText.bodyStrong),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final n in i.notes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                [n.version, if (n.date != null) DateFormat('MMM d, y').format(n.date!)].join(' · '),
                                style: AppText.overline,
                              ),
                              const SizedBox(height: 4),
                              Text(_plain(n.body), style: AppText.secondary),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (_progress != null) ...[
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 8),
                  Text('Downloading ${(_progress! * 100).round()}%', style: AppText.secondary),
                ] else if (!i.canInstall)
                  Text('No download for this phone in that release.', style: AppText.secondary)
                else
                  FilledButton.icon(
                    onPressed: _install,
                    icon: const Icon(Icons.system_update_alt),
                    label: Text(_apk == null ? 'Download and install' : 'Install'),
                  ),
                const SizedBox(height: 6),
                Text('Your contacts are kept. Android asks you to confirm the install.', style: AppText.secondary),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: AppText.body.copyWith(color: Tokens.hotFg)),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: i == null ? _check : _install, child: const Text('Try again')),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Release notes are Markdown from the CHANGELOG; show them as plain text and
  /// rejoin the hard-wrapped lines (an indented line continues the one above).
  static String _plain(String md) => md
      .replaceAll(RegExp(r'\r?\n[ \t]+(?=\S)'), ' ')
      .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
      .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m[1]!)
      .replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '• ')
      .trim();
}
