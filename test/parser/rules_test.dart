import 'package:card_organizer/parser/ocr.dart';
import 'package:card_organizer/parser/rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classic US card', () {
    final c = parseCard(OcrPage.fromText([
      'NORTHWIND FORGING, INC.',
      'Dana Reyes, PE',
      'VP Procurement',
      '1200 Industrial Pkwy, Suite 4',
      'Streetsboro, OH 44241',
      'M 330-555-0101  O (330) 555-0199',
      'F 330.555.0150',
      'dana.reyes@northwindforging.com',
      'www.northwindforging.com',
    ], heights: [14, 22, 11, 9, 9, 9, 9, 9, 9]));

    expect(c.name?.value, 'Dana Reyes');
    expect(c.suffix?.value, 'PE');
    expect(c.title?.value, 'VP Procurement');
    expect(c.company?.value, 'NORTHWIND FORGING, INC.');
    expect(c.address?.value, '1200 Industrial Pkwy, Suite 4, Streetsboro, OH 44241');
    expect(c.emails.single.value, 'dana.reyes@northwindforging.com');
    expect(c.website?.value, 'www.northwindforging.com');
    final mobile = c.phones.firstWhere((p) => p.label == 'mobile');
    expect(mobile.value, '+13305550101');
    expect(c.phones.where((p) => p.label == 'office').single.value, '+13305550199');
    expect(c.notes, contains('Fax: +13305550150'));
    expect(c.needsReview, isFalse);
  });

  test('company from domain when no legal suffix', () {
    final c = parseCard(OcrPage.fromText([
      'Brightline',
      'SAM OKAFOR',
      'Head of Sales',
      'sam@brightline.io',
      'Cell: +1 216 555 0123',
    ], heights: [16, 20, 10, 9, 9]));
    expect(c.company?.value, 'Brightline');
    expect(c.name?.value, 'Sam Okafor');
    expect(c.title?.value, 'Head of Sales');
    expect(c.phones.single.label, 'mobile');
    expect(c.website, isNull);
  });

  test('low confidence is flagged for review', () {
    final c = parseCard(const OcrPage([
      const OcrLine('Ana Lima', height: 20, confidence: 0.5),
      const OcrLine('ana@acme.com', height: 9),
    ]));
    expect(c.name!.needsReview, isTrue);
    expect(c.needsReview, isTrue);
  });

  test('unassigned lines go to notes', () {
    final c = parseCard(OcrPage.fromText([
      'Acme Corp', 'Jo Park', 'Engineer', 'Booth 1442 – ask about tooling'
    ], heights: [14, 20, 10, 8]));
    expect(c.notes, contains('Booth 1442 – ask about tooling'));
  });

  test('UK address and phone with region', () {
    final c = parseCard(
        OcrPage.fromText([
          'Harbour Tools Ltd',
          'Priya Shah',
          'Purchasing Manager',
          '14 Dock Road',
          'Bristol BS1 6QA',
          'T: 0117 496 0123',
        ], heights: [14, 20, 10, 9, 9, 9]),
        region: 'GB');
    expect(c.address?.value, '14 Dock Road, Bristol BS1 6QA');
    expect(c.phones.single.value, '+441174960123');
  });

  test('OcrPage json round-trip', () {
    const p = OcrPage([OcrLine('x', left: 1, top: 2, width: 3, height: 4, confidence: .8)]);
    expect(OcrPage.fromJson(p.toJson()).lines.single.confidence, .8);
  });
}
