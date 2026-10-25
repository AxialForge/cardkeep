import 'dart:io';

import 'package:card_organizer/features/about/changelog_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _md = '''
# Changelog

All notable changes to CardKeep.

## [0.7.4] - 2026-10-25

### Added

- **App lock**: ask for your fingerprint
  or passcode to open CardKeep.
- Delete everything.

### Fixed

- A `thing`.

## [0.7.3] - 2026-10-24

### Added

- Guided tour.
''';

void main() {
  test('parseChangelog turns versions, sections and bullets into lines', () {
    final l = parseChangelog(_md);
    expect(l.first.kind, ChangelogKind.text, reason: 'the intro line; the file title is skipped');
    expect(l.where((x) => x.kind == ChangelogKind.version).map((x) => x.text), [
      '0.7.4 - 2026-10-25',
      '0.7.3 - 2026-10-24',
    ]);
    expect(l.where((x) => x.kind == ChangelogKind.section).map((x) => x.text), ['Added', 'Fixed', 'Added']);
    final bullets = l.where((x) => x.kind == ChangelogKind.bullet).map((x) => x.text).toList();
    expect(
      bullets[0],
      'App lock: ask for your fingerprint or passcode to open CardKeep.',
      reason: 'wrapped lines join; bold dropped',
    );
    expect(bullets[2], 'A thing.', reason: 'backticks dropped');
  });

  test('links keep their label, Unreleased is renamed and stray markdown goes (real CHANGELOG lines)', () {
    final l = parseChangelog('''
# Changelog

All notable changes to CardKeep. Format: [Keep a Changelog](https://keepachangelog.com/), versions: [SemVer](https://semver.org/).

## [Unreleased]

### Added

- **Four more looks** for the theme pills: **Harbor** and _Midnight Ink_, with `system:<id>` kept.
''');
    expect(l.first.text, 'All notable changes to CardKeep. Format: Keep a Changelog, versions: SemVer.');
    final v = l.firstWhere((x) => x.kind == ChangelogKind.version);
    expect(v.text, 'Coming in the next version');
    final b = l.firstWhere((x) => x.kind == ChangelogKind.bullet).text;
    expect(b, 'Four more looks for the theme pills: Harbor and Midnight Ink, with system:<id> kept.');
    expect(b.contains('**') || b.contains('`') || b.contains('_') || b.contains(']('), isFalse);
  });

  testWidgets('the changelog screen shows the text it is given at 200% font', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: ChangelogScreen(source: Future.value(_md)),
      ),
    );
    await tester.pump();
    expect(find.text('0.7.4 - 2026-10-25'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a changelog that cannot be loaded says so instead of crashing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangelogScreen(
          source: Future<String>(() async {
            await Future<void>.delayed(Duration.zero);
            throw 'gone';
          }),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('The changelog could not be loaded.'), findsOneWidget);
  });

  test('the bundled CHANGELOG.md parses and starts with a released or unreleased version', () {
    // Reads the real file from the project root.
    final text = File('CHANGELOG.md').readAsStringSync();
    final v = parseChangelog(text).where((x) => x.kind == ChangelogKind.version).toList();
    expect(v, isNotEmpty);
  });
}
