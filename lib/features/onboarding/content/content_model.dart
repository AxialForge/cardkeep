/// The tour's words, as plain data (S15a.9). No Flutter imports: the tour, the
/// Help hub, the tests and the user manual all read the same lists, so what the
/// app teaches cannot drift from what the Help hub says.
library;

/// Which animated illustration goes with a page (drawn in `lesson_art.dart`).
enum Art {
  welcome,
  privacy,
  keeps,
  tour,
  scanOne,
  sweep,
  queue,
  personPlace,
  organise,
  importExport,
  backup,
  nfc,
  myCard,
  camera,
  bell,
  nfcPhone,
  setup,
  demo,
  help,
}

/// One numbered step of a lesson or article.
class LessonStep {
  final String title;
  final String body;
  const LessonStep(this.title, this.body);
}

enum HelpGroup {
  start('Start here'),
  scanning('Scanning'),
  organise('Organising'),
  data('Your data'),
  trouble('Troubleshooting');

  final String label;
  const HelpGroup(this.label);
}

/// A lesson in the tour and an article in Help & tips (lessons are articles
/// with [lesson] set, in tour order).
class HelpArticle {
  final String id;
  final String title;
  final String summary;
  final HelpGroup group;
  final Art art;
  final List<LessonStep> steps;

  /// One extra line shown under the steps.
  final String? tip;

  /// "Try it": the real screen to open and the coach-mark tip to show there.
  final String? tryLabel;
  final String? tryRoute;
  final String? coachId;
  final List<String> keywords;
  final bool lesson;

  const HelpArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.group,
    required this.art,
    required this.steps,
    this.tip,
    this.tryLabel,
    this.tryRoute,
    this.coachId,
    this.keywords = const [],
    this.lesson = false,
  });

  /// Everything searchable, lower case.
  String get haystack => [
    title,
    summary,
    ...steps.expand((s) => [s.title, s.body]),
    ?tip,
    ...keywords,
  ].join(' ').toLowerCase();
}

/// Articles whose text contains every word of [query] (empty query = all).
List<HelpArticle> searchArticles(List<HelpArticle> all, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return all;
  return [
    for (final a in all)
      if (words.every(a.haystack.contains)) a,
  ];
}

/// One page of the welcome section.
class WelcomePage {
  final String id;
  final Art art;
  final String title;
  final String lead;
  final List<LessonStep> points;
  const WelcomePage(this.id, this.art, this.title, this.lead, this.points);
}

/// A permission card (S15a.2). [kind] names what the app can actually ask for;
/// null means there is nothing to grant (NFC, contacts).
enum PermKind { camera, notifications }

class PermissionCardInfo {
  final String id;
  final Art art;
  final String title;
  final PermKind? kind;
  final String why;
  final String never;
  final String ifNo;
  final String later;
  const PermissionCardInfo({
    required this.id,
    required this.art,
    required this.title,
    required this.kind,
    required this.why,
    required this.never,
    required this.ifNo,
    required this.later,
  });
}

/// How to bring contacts in from somewhere else (finale, S15a.6).
class ImportHowTo {
  final String id;
  final String source;
  final List<String> steps;
  const ImportHowTo(this.id, this.source, this.steps);
}
