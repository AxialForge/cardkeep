import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';

/// One block of the changelog, ready to draw.
class ChangelogLine {
  final ChangelogKind kind;
  final String text;
  const ChangelogLine(this.kind, this.text);
}

enum ChangelogKind { version, section, bullet, text }

/// Turns CHANGELOG.md into lines to draw: `## [0.7.3] - date` becomes a version
/// heading, `### Added` a section heading, `- ` a bullet (its wrapped lines join
/// it) and anything else plain text. `**bold**` and backticks are dropped.
List<ChangelogLine> parseChangelog(String markdown) {
  final out = <ChangelogLine>[];
  String clean(String s) => s.replaceAll('**', '').replaceAll('`', '').trim();
  for (final raw in markdown.replaceAll('\r\n', '\n').split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) continue;
    if (line.startsWith('# ')) continue; // the file's own title
    if (line.startsWith('## ')) {
      final t = clean(line.substring(3)).replaceAll('[', '').replaceAll(']', '');
      out.add(ChangelogLine(ChangelogKind.version, t));
    } else if (line.startsWith('### ')) {
      out.add(ChangelogLine(ChangelogKind.section, clean(line.substring(4))));
    } else if (line.startsWith('- ') || line.startsWith('* ')) {
      out.add(ChangelogLine(ChangelogKind.bullet, clean(line.substring(2))));
    } else if (raw.startsWith('  ') && out.isNotEmpty && out.last.kind == ChangelogKind.bullet) {
      out[out.length - 1] = ChangelogLine(ChangelogKind.bullet, '${out.last.text} ${clean(line)}');
    } else {
      out.add(ChangelogLine(ChangelogKind.text, clean(line)));
    }
  }
  return out;
}

/// What's changed: the bundled changelog, newest first as written.
class ChangelogScreen extends StatelessWidget {
  /// For tests; the app reads the bundled file.
  final Future<String>? source;
  const ChangelogScreen({super.key, this.source});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('What\'s changed')),
    body: FutureBuilder<String>(
      future: source ?? rootBundle.loadString('CHANGELOG.md'),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text('The changelog could not be loaded.', style: AppText.secondary),
            ),
          );
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final lines = parseChangelog(snap.data!);
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          itemCount: lines.length,
          itemBuilder: (_, i) {
            final l = lines[i];
            return switch (l.kind) {
              ChangelogKind.version => Semantics(
                header: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: 22, bottom: 4),
                  child: Text(l.text, style: AppText.heading),
                ),
              ),
              ChangelogKind.section => Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                child: Text(l.text.toUpperCase(), style: AppText.overline),
              ),
              ChangelogKind.bullet => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text('•', style: AppText.body),
                    ),
                    Expanded(child: Text(l.text, style: AppText.body)),
                  ],
                ),
              ),
              ChangelogKind.text => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(l.text, style: AppText.secondary),
              ),
            };
          },
        );
      },
    ),
  );
}
