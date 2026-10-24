import 'package:card_organizer/features/onboarding/content/content_model.dart';
import 'package:card_organizer/features/onboarding/content/help_content.dart';
import 'package:card_organizer/features/onboarding/content/welcome_content.dart';
import 'package:card_organizer/features/onboarding/lesson_art.dart';
import 'package:card_organizer/features/onboarding/onboarding_gate.dart';
import 'package:flutter_test/flutter_test.dart';

/// The screens a "Try it" button may open (all registered in the router).
const knownRoutes = {
  '/scan',
  '/scan?mode=sweep',
  '/queue',
  '/contact/new',
  '/duplicates',
  '/export',
  '/tap',
  '/mycard',
  '/settings',
  '/import',
};

void main() {
  group('lessons and help articles', () {
    test('there are eight lessons, in teaching order, each marked as a lesson', () {
      expect(lessons.length, 8);
      expect(lessons.every((l) => l.lesson), isTrue);
      expect(faq.any((a) => a.lesson), isFalse);
    });

    test('every id is unique across lessons and answers', () {
      final ids = helpArticles.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every lesson has two to four steps; every answer at least one', () {
      for (final l in lessons) {
        expect(l.steps.length, inInclusiveRange(2, 4), reason: l.id);
      }
      for (final a in helpArticles) {
        expect(a.steps, isNotEmpty, reason: a.id);
        expect(a.title.trim(), isNotEmpty, reason: a.id);
        expect(a.summary.trim(), isNotEmpty, reason: a.id);
        for (final s in a.steps) {
          expect(s.title.trim(), isNotEmpty, reason: a.id);
          expect(s.body.trim().length, greaterThan(20), reason: '${a.id}: ${s.title}');
        }
      }
    });

    test('Try it points at a real screen, and a coach tip only comes with a screen', () {
      for (final a in helpArticles) {
        if (a.tryRoute != null) {
          expect(knownRoutes, contains(a.tryRoute), reason: a.id);
          expect(a.tryLabel, isNotNull, reason: a.id);
        } else {
          expect(a.coachId, isNull, reason: a.id);
          expect(a.tryLabel, isNull, reason: a.id);
        }
      }
    });

    test('every article belongs to a group, and the Help hub shows no empty group', () {
      for (final g in HelpGroup.values) {
        expect(helpArticles.where((a) => a.group == g), isNotEmpty, reason: g.name);
      }
    });

    test('the copy never promises or mentions database encryption (declined)', () {
      final all = [
        for (final a in helpArticles) a.haystack,
        for (final w in welcomePages)
          '${w.title} ${w.lead} ${w.points.map((p) => '${p.title} ${p.body}').join(' ')}'.toLowerCase(),
        for (final p in permissionCards) '${p.why} ${p.never} ${p.ifNo} ${p.later}'.toLowerCase(),
      ].join(' ');
      expect(all.contains('encrypt'), isFalse);
    });

    test('the copy makes no claim the app does not keep', () {
      final all = [for (final a in helpArticles) a.haystack].join(' ');
      expect(all.contains('analytics'), isTrue, reason: 'says there are none');
      expect(all.contains('sign in'), isFalse);
      expect(all.contains('cloud backup'), isTrue, reason: 'says Android cloud backup is off');
    });

    test('every illustration has a description for TalkBack', () {
      for (final a in Art.values) {
        expect(artDescription(a).trim().length, greaterThan(10), reason: a.name);
      }
      for (final a in helpArticles) {
        expect(artDescription(a.art), isNotEmpty);
      }
    });
  });

  group('welcome, permissions and import how-tos', () {
    test('four welcome pages with three or more points each, ending in how the tour works', () {
      expect(welcomePages.length, 4);
      expect(welcomePages.last.id, 'how');
      for (final w in welcomePages) {
        expect(w.points.length, greaterThanOrEqualTo(3), reason: w.id);
      }
      expect(welcomePages.map((w) => w.id).toSet().length, 4);
    });

    test('the privacy page states the real limits', () {
      final text = welcomePages[1].points.map((p) => '${p.title} ${p.body}').join(' ');
      expect(text, contains('GitHub'));
      expect(text, contains('ML Kit'));
      expect(text, contains('cloud backup'));
    });

    test('three permission cards: camera and notifications can be asked, NFC cannot', () {
      expect(permissionCards.map((p) => p.id), ['camera', 'notifications', 'nfc']);
      expect(permissionCards[0].kind, PermKind.camera);
      expect(permissionCards[1].kind, PermKind.notifications);
      expect(permissionCards[2].kind, isNull);
      for (final p in permissionCards) {
        expect(p.why, isNotEmpty);
        expect(p.never, isNotEmpty);
        expect(p.ifNo, isNotEmpty);
        expect(p.later, isNotEmpty);
      }
    });

    test('the contacts permission is explained as never asked', () {
      expect(permissionCards.last.why.toLowerCase(), contains('never asks to read your phone'));
    });

    test('import how-tos cover Google, Outlook, iPhone and LinkedIn', () {
      expect(importHowTos.map((h) => h.id), ['google', 'outlook', 'iphone', 'linkedin']);
      for (final h in importHowTos) {
        expect(h.steps.length, greaterThanOrEqualTo(3), reason: h.id);
      }
    });
  });

  group('search', () {
    test('an empty query returns everything', () {
      expect(searchArticles(helpArticles, '').length, helpArticles.length);
      expect(searchArticles(helpArticles, '   ').length, helpArticles.length);
    });

    test('finds by title, step text and keyword, case-insensitively', () {
      expect(searchArticles(helpArticles, 'BACKUPS').map((a) => a.id), contains('backups'));
      expect(searchArticles(helpArticles, 'torch').map((a) => a.id), contains('blurry'));
      expect(searchArticles(helpArticles, 'popl').map((a) => a.id), contains('tap-cards'));
    });

    test('several words must all match', () {
      final both = searchArticles(helpArticles, 'new phone restore');
      expect(both.map((a) => a.id), contains('new-phone'));
      expect(searchArticles(helpArticles, 'zebra quantum'), isEmpty);
    });
  });

  group('version', () {
    test('the tour version is the release it ships in', () {
      expect(tourVersion, '0.7.3');
    });
  });
}
