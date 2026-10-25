// The Millennium card (Sweep test, 2026-10-23): the review queue showed "CSia"
// with "No name found" because the name and the title came off the card joined,
// or with an odd mark or case, and the line fell through to a tagline or a note.
import 'package:card_organizer/parser/ocr.dart';
import 'package:card_organizer/parser/rules.dart';
import 'package:flutter_test/flutter_test.dart';

ParsedCard parse(List<String> lines, [List<double>? heights]) => parseCard(OcrPage.fromText(lines, heights: heights));

const _tail = [
  'Corporate Office',
  '1200 Industrial Pkwy',
  'Akron, OH 44310',
  'Mobile 330 555 0142',
  'Office 330 555 0100',
  'ssoto@millenniumcontrolsystems.example',
  'www.millenniumcontrolsystems.example',
];

void expectSteve(ParsedCard c) {
  expect(c.name?.value, 'Steve Soto');
  expect(c.title?.value, 'Manager of QSE');
  expect(c.company?.value, 'CSia');
  expect(c.toFields()['mobile'], '+13305550142');
  expect(c.notes, ['Corporate Office']);
}

void main() {
  test('name and title on separate lines', () {
    expectSteve(parse(['CSia', 'Steve Soto', 'Manager of QSE', ..._tail]));
  });

  test('name / title on one line split at the slash instead of becoming a tagline', () {
    expectSteve(parse(['CSia', 'Steve Soto / Manager of QSE', ..._tail]));
  });

  test('name and title run together are split when the email backs the name up', () {
    expectSteve(parse(['CSia', 'Steve Soto Manager of QSE', ..._tail]));
  });

  test('a name read in odd case is still the name when the email backs it up', () {
    final c = parse(['CSia', 'Steve soto', 'Manager of QSE', ..._tail]);
    expect(c.name?.value, 'Steve Soto');
    expect(c.title?.value, 'Manager of QSE');
    expect(c.company?.value, 'CSia');
  });

  test('a job title alone is not cut into a name and a title', () {
    final c = parse(['Acme Tools', 'Senior Vice President', 'Jordan Pike', 'jpike@acmetools.example']);
    expect(c.name?.value, 'Jordan Pike');
    expect(c.title?.value, 'Senior Vice President');
  });

  test('dashes and bars in other lines are left alone', () {
    final c = parse(['Acme Tools', 'Sales - Service - Parts', 'Jordan Pike', 'jpike@acmetools.example']);
    expect(c.name?.value, 'Jordan Pike');
    expect(c.company?.value, 'Acme Tools');
  });
}
