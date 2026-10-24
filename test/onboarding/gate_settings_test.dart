import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/demo/demo_data.dart';
import 'package:card_organizer/core/settings/settings_repository.dart';
import 'package:card_organizer/core/tags/tags_repository.dart';
import 'package:card_organizer/features/onboarding/onboarding_gate.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('first launch vs upgrade routing', () {
    test('a new user with an empty library gets the tour', () {
      expect(decideOnboarding(doneVersion: null, whatsNewSeen: null, hasData: false), OnboardingStart.tour);
    });

    test('someone upgrading with data gets the What\'s new sheet once', () {
      expect(decideOnboarding(doneVersion: null, whatsNewSeen: null, hasData: true), OnboardingStart.whatsNew);
      expect(decideOnboarding(doneVersion: null, whatsNewSeen: tourVersion, hasData: true), OnboardingStart.none);
    });

    test('an older sheet does not hide the current one', () {
      expect(decideOnboarding(doneVersion: null, whatsNewSeen: '0.7.2', hasData: true), OnboardingStart.whatsNew);
    });

    test('finishing or skipping the tour means never again', () {
      for (final data in [true, false]) {
        expect(decideOnboarding(doneVersion: tourVersion, whatsNewSeen: null, hasData: data), OnboardingStart.none);
      }
    });
  });

  group('coach-mark show-once rule', () {
    test('shows only when tips are on and the tip is unseen', () {
      expect(shouldShowTip('a', tipsEnabled: true, seen: {}), isTrue);
      expect(shouldShowTip('a', tipsEnabled: true, seen: {'a'}), isFalse);
      expect(shouldShowTip('a', tipsEnabled: false, seen: {}), isFalse);
      expect(shouldShowTip('b', tipsEnabled: true, seen: {'a'}), isTrue);
    });

    test('Try it forces exactly that tip, even when off or seen', () {
      expect(shouldShowTip('a', tipsEnabled: false, seen: {'a'}, forced: 'a'), isTrue);
      expect(shouldShowTip('a', tipsEnabled: false, seen: {}, forced: 'b'), isFalse);
    });
  });

  group('onboarding settings', () {
    late AppDatabase db;
    late SettingsRepository s;
    setUp(() {
      db = memoryDb();
      s = SettingsRepository(db);
    });
    tearDown(() => db.close());

    test('nothing is saved at first', () async {
      expect(await s.onboardingVersion(), isNull);
      expect(await s.whatsNewSeen(), isNull);
      expect(await s.tipsEnabled(), isFalse);
      expect(await s.tipsSeen(), isEmpty);
    });

    test('the finished version persists', () async {
      await s.setOnboardingVersion(tourVersion);
      expect(await s.onboardingVersion(), tourVersion);
      expect(await s.watchOnboardingVersion().first, tourVersion);
      await s.setWhatsNewSeen(tourVersion);
      expect(await s.whatsNewSeen(), tourVersion);
    });

    test('seen tips accumulate without duplicates', () async {
      await s.markTipSeen('contacts');
      await s.markTipSeen('scan');
      await s.markTipSeen('contacts');
      expect(await s.tipsSeen(), {'contacts', 'scan'});
      expect(await s.watchTipsSeen().first, {'contacts', 'scan'});
    });

    test('Reset tips clears what was seen and turns tips on', () async {
      await s.markTipSeen('contacts');
      await s.setTipsEnabled(false);
      await s.resetTips();
      expect(await s.tipsSeen(), isEmpty);
      expect(await s.tipsEnabled(), isTrue);
    });
  });

  group('demo data', () {
    late AppDatabase db;
    late ContactsRepository contacts;
    late TagsRepository tags;
    late DemoData demo;
    setUp(() {
      db = memoryDb();
      contacts = ContactsRepository(db);
      tags = TagsRepository(db, contacts);
      demo = DemoData(db, contacts, tags);
    });
    tearDown(() => db.close());

    test('adds six fictional contacts, one of them a place, all tagged Demo', () async {
      expect(await demo.add(), 6);
      expect(await demo.count(), 6);
      final list = await contacts.watchContacts(const ContactFilter()).first;
      expect(list.length, 6);
      expect(list.where((c) => c.isPlace).length, 1);
      final demoTag = (await tags.watchTags().first).singleWhere((t) => t.name == 'Demo');
      expect(demoTag.count, 6);
    });

    test('everything in it is obviously made up', () {
      for (final d in DemoData.samples()) {
        expect(d.notes, DemoData.note);
        for (final p in d.phones) {
          expect(p.value, contains('555'));
        }
        for (final e in d.emails) {
          expect(e, endsWith('.example'));
        }
      }
    });

    test('a second add adds nothing while the demo is there', () async {
      await demo.add();
      expect(await demo.add(), 0);
      expect(await demo.count(), 6);
    });

    test('Remove takes every demo contact and the tag, and leaves your own', () async {
      await contacts.save(ContactDraft(first: 'Real', last: 'Person', company: 'Mine Ltd'));
      await demo.add();
      expect(await demo.remove(), 6);
      expect(await demo.count(), 0);
      final left = await contacts.watchContacts(const ContactFilter()).first;
      expect(left.map((c) => c.displayName), ['Real Person']);
      expect((await tags.watchTags().first).where((t) => t.name == 'Demo'), isEmpty);
    });

    test('after removing, the demo can be added again', () async {
      await demo.add();
      await demo.remove();
      expect(await demo.add(), 6);
      expect(await demo.count(), 6);
    });

    test('the live count follows adds and removes', () async {
      final seen = <int>[];
      final sub = demo.watchCount().listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await demo.add();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await demo.remove();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      expect(seen.first, 0);
      expect(seen, contains(6));
      expect(seen.last, 0);
    });
  });
}
