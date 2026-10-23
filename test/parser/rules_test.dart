import 'package:card_organizer/parser/ocr.dart';
import 'package:card_organizer/parser/rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classic US card', () {
    final c = parseCard(
      OcrPage.fromText(
        [
          'NORTHWIND FORGING, INC.',
          'Dana Reyes, PE',
          'VP Procurement',
          '1200 Industrial Pkwy, Suite 4',
          'Streetsboro, OH 44241',
          'M 330-555-0101  O (330) 555-0199',
          'F 330.555.0150',
          'dana.reyes@northwindforging.com',
          'www.northwindforging.com',
        ],
        heights: [14, 22, 11, 9, 9, 9, 9, 9, 9],
      ),
    );

    expect(c.name?.value, 'Dana Reyes');
    expect(c.suffix?.value, 'PE');
    expect(c.title?.value, 'VP Procurement');
    expect(c.company?.value, 'Northwind Forging, Inc.', reason: 'capitals re-cased (0.6.2 phone test F11)');
    expect(c.address?.value, '1200 Industrial Pkwy, Suite 4, Streetsboro, OH 44241');
    expect(c.emails.single.value, 'dana.reyes@northwindforging.com');
    expect(c.website?.value, 'www.northwindforging.com');
    final mobile = c.phones.firstWhere((p) => p.label == 'mobile');
    expect(mobile.value, '+13305550101');
    expect(c.phones.where((p) => p.label == 'office').single.value, '+13305550199');
    expect(c.faxes.single.value, '+13305550150');
    expect(c.needsReview, isFalse);
  });

  test('extensions, fax, re-cased capitals and sorted extras (S10b)', () {
    final c = parseCard(
      OcrPage.fromText(
        [
          'ENPRESS LLC',
          'FRED PANETO',
          'PLANT MANAGER',
          'Direct (440) 571-0609',
          'Tel. (440) 510-0108 Ext. 112',
          'Fax (440) 510-0202',
          'E-Mail fpaneto@enpress.com',
          'Where Innovation Flows',
          'Lic. # 48213',
          'Mon-Fri 7am - 5pm',
        ],
        heights: [16, 20, 10, 9, 9, 9, 9, 8, 8, 8],
      ),
    );
    expect(c.name?.value, 'Fred Paneto');
    expect(c.phones.map((p) => (p.value, p.extension)), contains(('+14405100108', '112')));
    expect(c.faxes.single.value, '+14405100202');
    expect(
      {for (final e in c.extras) e.label: e.value},
      {'Tagline': 'Where Innovation Flows', 'Licence': 'Lic. # 48213', 'Hours': 'Mon-Fri 7am - 5pm'},
    );
  });

  test('the real ENPRESS card as ML Kit read it on the phone', () {
    final c = parseCard(
      OcrPage.fromText(
        [
          'ENPRESS LLC',
          'FRED PANETO',
          'PLANT MANAGER',
          'Direct (440)57I-0609',
          'Tel. (440)510-0108 Ext. I12',
          'Fax (440)510-0202',
          'E-Mail fpaneto@enpress.com',
          '34899 Curtis Blvd.',
          'Eastlake, Ohio 44095',
          'www.enpress.com',
        ],
        heights: [16, 20, 10, 9, 9, 9, 9, 9, 9, 9],
      ),
    );
    expect(c.title?.value, 'Plant Manager');
    expect(c.phones.map((p) => (p.value, p.extension)).toSet(), {('+14405710609', ''), ('+14405100108', '112')});
    expect(c.address?.value, '34899 Curtis Blvd., Eastlake, Ohio 44095');
    expect(c.notes, isEmpty, reason: 'the "E-Mail" label is not a note');
  });

  test('digit look-alikes are fixed only inside numbers', () {
    expect(fixDigitLookalikes('(440)57I-0609'), '(440)571-0609');
    expect(fixDigitLookalikes('Ext. I12'), 'Ext. 112');
    expect(fixDigitLookalikes('330-555-O1O1'), '330-555-0101');
    expect(fixDigitLookalikes('Ohio 44095'), 'Ohio 44095');
    expect(fixDigitLookalikes('Lic. # 48213 Illinois'), 'Lic. # 48213 Illinois');
  });

  test('titles in capitals are re-cased, acronyms kept', () {
    expect(titleCaseTitle('PLANT MANAGER'), 'Plant Manager');
    expect(titleCaseTitle('VP OF SALES AND MARKETING'), 'VP of Sales and Marketing');
    expect(titleCaseTitle('CEO'), 'CEO');
    expect(titleCaseTitle('Head of IT'), 'Head of IT');
  });

  test('name casing keeps Mc, O\', hyphens and initials', () {
    expect(titleCaseName('MARY-KATE MCDONALD'), 'Mary-Kate McDonald');
    expect(titleCaseName("SEAN O'BRIEN"), "Sean O'Brien");
    expect(titleCaseName('DANA K. REYES'), 'Dana K. Reyes');
    expect(titleCaseName('JOHN SMITH III'), 'John Smith III');
    expect(titleCaseName('McAllister'), 'McAllister');
  });

  test('company from domain when no legal suffix', () {
    final c = parseCard(
      OcrPage.fromText(
        ['Brightline', 'SAM OKAFOR', 'Head of Sales', 'sam@brightline.io', 'Cell: +1 216 555 0123'],
        heights: [16, 20, 10, 9, 9],
      ),
    );
    expect(c.company?.value, 'Brightline');
    expect(c.name?.value, 'Sam Okafor');
    expect(c.title?.value, 'Head of Sales');
    expect(c.phones.single.label, 'mobile');
    expect(c.website, isNull);
  });

  test('low confidence is flagged for review', () {
    final c = parseCard(
      const OcrPage([OcrLine('Ana Lima', height: 20, confidence: 0.3), OcrLine('ana@acme.com', height: 9)]),
    );
    expect(c.name!.needsReview, isTrue);
    expect(c.needsReview, isTrue);
  });

  test('unassigned lines go to notes', () {
    final c = parseCard(
      OcrPage.fromText(
        ['Acme Corp', 'Jo Park', 'Engineer', 'Booth 1442 – ask about tooling'],
        heights: [14, 20, 10, 8],
      ),
    );
    expect(c.notes, contains('Booth 1442 – ask about tooling'));
  });

  test('UK address and phone with region', () {
    final c = parseCard(
      OcrPage.fromText(
        [
          'Harbour Tools Ltd',
          'Priya Shah',
          'Purchasing Manager',
          '14 Dock Road',
          'Bristol BS1 6QA',
          'T: 0117 496 0123',
        ],
        heights: [14, 20, 10, 9, 9, 9],
      ),
      region: 'GB',
    );
    expect(c.address?.value, '14 Dock Road, Bristol BS1 6QA');
    expect(c.phones.single.value, '+441174960123');
  });

  test('emails broken by OCR spaces are rejoined (S2.11)', () {
    final c = parseCard(mlkitSam());
    expect(c.emails.single.value, 'sam@brightline.io');
    expect(parseCard(OcrPage.fromText(['dana . reyes @ acme . com'])).emails.single.value, 'dana.reyes@acme.com');
  });

  test('weighted confidence with real ML Kit values lets clear fields pass 0.85 (S2.7)', () {
    final c = parseCard(mlkitSam());
    expect(c.name!.value, 'Sam Okafor');
    expect(c.name!.confidence, greaterThanOrEqualTo(0.85), reason: 'name found in the email: cross-check passes');
    expect(c.phones.single.confidence, greaterThanOrEqualTo(0.85));
    expect(c.emails.single.confidence, greaterThanOrEqualTo(0.85));
    expect(c.needsReview, isFalse);
  });

  test('OcrPage json round-trip', () {
    const p = OcrPage([OcrLine('x', left: 1, top: 2, width: 3, height: 4, confidence: .8)]);
    expect(OcrPage.fromJson(p.toJson()).lines.single.confidence, .8);
  });
}

/// Lines and confidences as ML Kit returned them on the emulator for a
/// synthetic card (S2.6: the Flutter plugin does report line confidence).
OcrPage mlkitSam() => const OcrPage([
  OcrLine('Brightline', top: 40, height: 30, confidence: 0.913),
  OcrLine('Sam Okafor', top: 160, height: 62, confidence: 0.862),
  OcrLine('Head of Sales', top: 250, height: 32, confidence: 0.885),
  OcrLine('Cell: +1 216 555 0123', top: 360, height: 28, confidence: 0.883),
  OcrLine('sam@brightline. io', top: 400, height: 28, confidence: 0.845),
]);

void mlkitTests() {}
