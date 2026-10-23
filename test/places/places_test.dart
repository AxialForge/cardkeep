import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/csv/csv_export.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/dupes/matcher.dart';
import 'package:card_organizer/core/transfer/csv_import.dart';
import 'package:card_organizer/core/vcard/vcard.dart';
import 'package:card_organizer/core/vcard/vcard_reader.dart';
import 'package:card_organizer/parser/ocr.dart';
import 'package:card_organizer/parser/place.dart';
import 'package:card_organizer/parser/rules.dart';
import 'package:card_organizer/scan/scan_pipeline.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Places (roadmap S14b): store, restaurant, vendor and service cards.
ParsedCard card(List<String> lines, [List<double>? heights]) =>
    parseCard(OcrPage.fromText(lines, heights: heights ?? [for (final (i, _) in lines.indexed) i == 0 ? 20.0 : 9.0]));

void main() {
  group('detection on scan (S14b.2)', () {
    test('a hardware store card with hours and an address is a place', () {
      final d = draftFromScan(
        card([
          'Lakeside Hardware',
          'Tools · Paint · Garden',
          '1420 Shore Rd, Euclid, OH 44123',
          'Mon-Fri 8am-7pm  Sat 9am-5pm',
          '(216) 555-0190',
          'lakesidehardware.example',
        ]),
      );
      expect(d.isPlace, isTrue);
      expect(d.company, 'Lakeside Hardware');
      expect(d.displayName, 'Lakeside Hardware');
      expect([d.first, d.last, d.title], ['', '', '']);
      expect(d.category, PlaceCategory.store);
      expect(d.hours, contains('8am-7pm'));
      expect(d.extras.where((e) => e.label == 'Hours'), isEmpty, reason: 'hours moved to their own field');
    });

    test('a cafe card with a slogan is a restaurant', () {
      final g = guessPlace(
        card(['Copper Kettle Cafe', 'Order online at copperkettle.example', 'Open daily 7am-3pm', '(440) 555-0133']),
      );
      expect(g, isNotNull);
      expect(g!.category, PlaceCategory.restaurant);
      expect(g.business, contains('Copper Kettle'));
    });

    test('a vendor card without a person is a vendor', () {
      final g = guessPlace(
        card([
          'NORTHCOAST FASTENER SUPPLY',
          'Wholesale bolts, nuts and anchors',
          '880 Industrial Pkwy, Cleveland, OH 44135',
          'Phone 216 555 0177',
          'orders@ncfastener.example',
        ]),
      );
      expect(g, isNotNull);
      expect(g!.category, PlaceCategory.vendor);
    });

    test('an auto repair card is a service', () {
      final d = draftFromScan(
        card([
          'Ridge Road Auto Repair',
          'Walk-ins welcome · Free estimates',
          '5120 Ridge Rd, Parma, OH 44129',
          '(440) 555-0166',
        ]),
      );
      expect(d.isPlace, isTrue);
      expect(d.category, PlaceCategory.service);
    });

    test("a person's card stays a person, even with an address and a company", () {
      final d = draftFromScan(
        card([
          'Dana Reyes',
          'Quality Engineer',
          'Halden Tooling Group',
          '1200 Industrial Pkwy, Streetsboro, OH 44241',
          'M 330 555 0142',
          'dana.reyes@halden.example',
        ]),
      );
      expect(d.isPlace, isFalse);
      expect([d.first, d.last], ['Dana', 'Reyes']);
    });

    test('a supply company with a named salesperson stays a person', () {
      expect(
        guessPlace(
          card([
            'Priya Natarajan',
            'Account Executive',
            'Brightline Medical Supply',
            '1200 Lakeview Pkwy, Suite 300, Cleveland, OH 44114',
            'priya@brightline.example',
          ]),
        ),
        isNull,
      );
    });
  });

  group('library', () {
    late AppDatabase db;
    late ContactsRepository contacts;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      contacts = ContactsRepository(db);
    });
    tearDown(() => db.close());

    test('a place saves with its business name, category and hours, and filters as Places', () async {
      final id = await contacts.save(
        ContactDraft(
          kind: PersonKind.place,
          first: 'ignored',
          title: 'ignored',
          company: 'Lakeside Hardware',
          category: PlaceCategory.store,
          hours: 'Mon-Fri 8-7',
          phones: [const LabeledValue('Office', '216 555 0190')],
          address: '1420 Shore Rd, Euclid, OH 44123',
        ),
      );
      await contacts.save(ContactDraft(first: 'Dana', last: 'Reyes', company: 'Halden'));

      final d = (await contacts.loadDetail(id))!;
      expect(d.isPlace, isTrue);
      expect(d.person.displayName, 'Lakeside Hardware');
      expect([d.person.first, d.person.last], ['', '']);
      expect(d.currentRole?.title, '');
      expect(d.currentRole?.company, 'Lakeside Hardware');
      expect(d.person.trackCareer, isFalse);
      expect(d.toDraft().hours, 'Mon-Fri 8-7');

      final all = await contacts.watchContacts(const ContactFilter()).first;
      expect(all.map((c) => c.displayName), ['Lakeside Hardware', 'Dana Reyes'], reason: 'places sort by name');
      final places = await contacts.watchContacts(const ContactFilter(placesOnly: true)).first;
      expect(places.single.isPlace, isTrue);
      expect(places.single.subtitle, 'Store');
      final found = await contacts.watchContacts(const ContactFilter(query: 'store')).first;
      expect(found.single.id, id, reason: 'search finds a place by its category');
    });
  });

  group('vCard and CSV', () {
    const shop = ExportContact(
      isOrg: true,
      company: 'Lakeside Hardware',
      phones: [(label: 'O', number: '+12165550190')],
      website: 'lakesidehardware.example',
      address: '1420 Shore Rd',
      hours: 'Mon-Fri 8-7',
    );

    test('a place round-trips as KIND:org (4.0) and X-ABShowAs:COMPANY (3.0)', () {
      for (final v in ['3.0', '4.0']) {
        final text = writeVCard(shop, version: v);
        expect(text, contains(v == '4.0' ? 'KIND:org' : 'X-ABShowAs:COMPANY'));
        expect(text, contains('FN:Lakeside Hardware'));
        final back = readVCards(text).single;
        expect(back.isOrg, isTrue, reason: v);
        expect(back.company, 'Lakeside Hardware');
        expect([back.first, back.last], ['', '']);
        expect(back.hours, 'Mon-Fri 8-7');
      }
    });

    test("an organisation vCard from another app (FN only) imports as a place", () {
      final c = readVCards('BEGIN:VCARD\r\nVERSION:4.0\r\nKIND:org\r\nFN:Copper Kettle Cafe\r\nEND:VCARD\r\n').single;
      expect(c.isOrg, isTrue);
      expect(c.company, 'Copper Kettle Cafe');
    });

    test('CardKeep CSV keeps the Type and Hours columns', () {
      final csv = writeCsv([shop, const ExportContact(first: 'Dana', last: 'Reyes')]);
      final rows = parseCsv(csv);
      final back = rowsToContacts(rows.skip(1).toList(), guessMapping(rows.first));
      expect(back.map((c) => c.isOrg), [true, false]);
      expect(back.first.hours, 'Mon-Fri 8-7');
    });
  });

  group('duplicates', () {
    MatchCandidate place(String id, String name, {Set<String>? phones, String address = ''}) =>
        MatchCandidate(id: id, name: name, company: name, isPlace: true, phones: phones, address: address);

    test('two places with the same name and phone match; a person never matches a place', () {
      final a = place('a', 'Lakeside Hardware', phones: {'+12165550190'});
      final b = place('b', 'Lakeside Hardware Inc', phones: {'+12165550190'});
      expect(matchPair(a, b)?.reason, MatchReason.place);
      expect(findPairs([a, b]).single.match.reason, MatchReason.place);
      final c = place('c', 'Lakeside Hardware', address: '1420 Shore Rd');
      final d = place('d', 'Lakeside Hardware', address: '1420 Shore Rd.');
      expect(matchPair(c, d), isNotNull, reason: 'same address');
      expect(matchPair(place('e', 'Lakeside Hardware'), place('f', 'Lakeside Hardware')), isNull, reason: 'name alone');
      final person = MatchCandidate(id: 'p', name: 'Lakeside Hardware', mobiles: {'+12165550190'});
      expect(matchPair(a, person), isNull);
    });
  });
}
