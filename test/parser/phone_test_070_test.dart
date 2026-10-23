// Lines as ML Kit read them from the 0.7.0 test card sheet on the owner's
// S25 Ultra (2026-10-23), docs/phone-tests/0.7.0-notes.md.
import 'package:card_organizer/core/db/tables.dart' show PlaceCategory;
import 'package:card_organizer/parser/ocr.dart';
import 'package:card_organizer/parser/place.dart';
import 'package:card_organizer/parser/rules.dart';
import 'package:card_organizer/scan/scan_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

ParsedCard parse(List<String> lines, [List<double>? heights]) => parseCard(OcrPage.fromText(lines, heights: heights));

void main() {
  group('card 5: Brightwater Family Dental', () {
    final card = parse(
      [
        'BRIGHTWATER',
        'Family Dental',
        'Dr. Elena M Kowalczyk DDS',
        '21 Ridge Rd, Hudson, OH 44236',
        '330 555 0150',
        'dr.k@brightwaterdental.example',
      ],
      [30, 22, 10, 9, 9, 9],
    );

    test('the Dr./DDS line is the name, not the large second logo line', () {
      expect(card.name?.value, 'Elena M Kowalczyk');
      expect(card.suffix?.value, 'Dr., DDS');
      final d = draftFromScan(card);
      expect([d.first, d.middle, d.last], ['Elena', 'M', 'Kowalczyk']);
    });

    test('company joined over two lines', () {
      expect(card.company?.value, 'Brightwater Family Dental');
    });

    test('details, and a person', () {
      expect(card.address?.value, '21 Ridge Rd, Hudson, OH 44236');
      expect(card.phones.single.value, '+13305550150');
      expect(card.emails.single.value, 'dr.k@brightwaterdental.example');
      expect(guessPlace(card), isNull);
    });
  });

  group('card 3: Reliable Fastener Supply', () {
    final card = parse(
      [
        'Reliable Fastener Supply',
        'Bolts, nuts, studs - same-day shipping',
        'Visit us: 2200 Industrial Pkwy',
        'Streetsboro, OH 44241',
        'Sales 330 555 0198',
        'sales@reliablefasteners.example',
      ],
      [16, 9, 9, 9, 9, 9],
    );

    test('"Sales" before a phone is a phone label, not a title', () {
      expect(card.title, isNull);
      expect(card.phones.single.value, '+13305550198');
      expect(card.phones.single.label, 'office');
    });

    test('"Visit us:" is not part of the address', () {
      expect(card.address?.value, '2200 Industrial Pkwy, Streetsboro, OH 44241');
    });

    test('still a vendor place', () {
      expect(guessPlace(card)?.category, PlaceCategory.vendor);
    });
  });

  group('card 4: Midtown Auto Repair', () {
    final card = parse(
      [
        'MIDTOWN AUTO REPAIR',
        'BRAKES - TIRES - OIL CHANGE - INSPECTIONS',
        'Mon-Fri 7:30-6:00',
        '1450 E 55th St, Cleveland, OH 44103',
        '216 555 0112',
        'midtownauto.example',
      ],
      [18, 8, 9, 9, 9, 9],
    );

    test('hours keep the space between days and time', () {
      expect(guessPlace(card)?.hours, 'Mon-Fri 7:30-6:00');
      // As the phone read it, with the space dropped.
      final squeezed = parse(
        [
          'MIDTOWN AUTO REPAIR',
          'BRAKES - TIRES - OIL CHANGE - INSPECTIONS',
          'Mon-Fri7:30-6:00',
          '1450 E 55th St, Cleveland, OH 44103',
          '216 555 0112',
          'midtownauto.example',
        ],
        [18, 8, 9, 9, 9, 9],
      );
      expect(guessPlace(squeezed)?.hours, 'Mon-Fri 7:30-6:00');
    });

    test('ALL CAPS tagline is kept and re-cased', () {
      final d = draftFromScan(card);
      expect(d.extras.where((e) => e.label == 'Tagline').map((e) => e.value), [
        'Brakes - Tires - Oil Change - Inspections',
      ]);
    });
  });
}
