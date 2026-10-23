// Cases from the 0.6.2 phone test (docs/phone-tests/0.6.2-results.md), using
// the line patterns ML Kit produced on the S25 Ultra.
import 'package:card_organizer/parser/ocr.dart';
import 'package:card_organizer/parser/rules.dart';
import 'package:card_organizer/scan/scan_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

ParsedCard parse(List<String> lines, [List<double>? heights]) => parseCard(OcrPage.fromText(lines, heights: heights));

void main() {
  test('F7: printed company on the back beats a logo word on the front', () {
    final front = parse(
      ['BECKER', 'TRAVIS DINGEE', 'Director of Sales & Operations', 'travis.dingee@beckerpumps.com'],
      [30, 16, 9, 8],
    );
    final back = parse(
      ['MAKE IT BECKER.', 'Becker Pumps Corporation', '100 East Ascot Lane', 'Cuyahoga Falls, OH 44223', 'USA'],
      [16, 9, 9, 9, 9],
    );
    expect(draftFromScan(front, back).company, 'Becker Pumps Corporation');
  });

  test('F7: a company guessed from the email loses to the printed one', () {
    final front = parse(
      ['Priya Natarajan', 'Account Executive', 'M 216 555 0133', 'priya@brightine.example'],
      [16, 9, 9, 9],
    );
    final back = parse(
      ['Brightline Medical Supply', '1200 Lakeview Pkwy, Suite 300', 'Cleveland, OH 44114', 'brightline.example'],
      [14, 9, 9, 9],
    );
    expect(back.company?.value, 'Brightline Medical Supply');
    expect(draftFromScan(front, back).company, 'Brightline Medical Supply');
  });

  test('F8: a label in its own column labels the number on the same row', () {
    final c = parseCard(
      const OcrPage([
        OcrLine('TRAVIS DINGEE', left: 30, top: 100, width: 200, height: 20),
        OcrLine('M', left: 30, top: 200, width: 10, height: 12),
        OcrLine('T', left: 30, top: 220, width: 10, height: 12),
        OcrLine('+1 234 280 5072', left: 70, top: 201, width: 120, height: 12),
        OcrLine('+1 888 633 1083', left: 70, top: 221, width: 120, height: 12),
      ]),
    );
    expect({for (final p in c.phones) p.value: p.label}, {'+12342805072': 'mobile', '+18886331083': 'office'});
    expect(c.notes, isEmpty);
  });

  test('F8: inline labels M, T, Tel, O, C, Cell, D, Direct', () {
    String label(String line) => parse([line]).phones.single.label;
    expect(label('M  +1 234 280 5072'), 'mobile');
    expect(label('C 330 555 0114'), 'mobile');
    expect(label('Cell: 330 555 0114'), 'mobile');
    expect(label('T  440 555 0170'), 'office');
    expect(label('Tel. 440 555 0170'), 'office');
    expect(label('O 234 555 0122'), 'office');
    expect(label('D 440 571 0577'), 'office');
    expect(label('Direct (440)571-0577'), 'office');
  });

  test('F9: a country line joins the address', () {
    final c = parse(['Becker Pumps Corporation', '100 East Ascot Lane', 'Cuyahoga Falls, OH 44223', 'USA']);
    expect(c.address?.value, '100 East Ascot Lane, Cuyahoga Falls, OH 44223, USA');
    expect(c.notes, isEmpty);
  });

  test('F10: a middle initial stuck to the first name is split', () {
    final c = parse(['PatrickJ. Walsh', 'Engineering Manager', 'VIKING FORGE'], [20, 10, 14]);
    expect(c.name?.value, 'Patrick J. Walsh');
    final d = draftFromScan(c);
    expect((d.first, d.middle, d.last), ('Patrick', 'J.', 'Walsh'));
  });

  test('F11: capitals title found, capitals company re-cased', () {
    final c = parse(
      ['THEODORE VANCE', 'SENIOR BUYER', 'NORTHWIND FORGING INC.', 'TEL 330 555 0190 EXT. 214', 'FAX 330 555 0191'],
      [20, 10, 12, 9, 9],
    );
    expect(c.name?.value, 'Theodore Vance');
    expect(c.title?.value, 'Senior Buyer');
    expect(c.company?.value, 'Northwind Forging Inc.');
    expect(titleCaseCompany('ENPRESS LLC'), 'Enpress LLC');
    expect(titleCaseCompany('H&S HORSBURGH & SCOTT'), 'H&S Horsburgh & Scott');
    expect(titleCaseCompany('ACME TOOLS USA'), 'Acme Tools USA');
    expect(titleCaseCompany('Becker Pumps Corporation'), 'Becker Pumps Corporation');
  });

  test('F12: small-caps misreads are not garbled', () {
    final c = parse(['Travis Dingee', 'Becker Pumps Corporation', 'VACUUM PUMPS | cOMPRESSORS | REGENERATIVE BLOWERs']);
    final text = [...c.notes, ...c.extras.map((e) => e.value)].join(' ');
    expect(text, contains('COMPRESSORS'));
    expect(text, contains('BLOWERS'));
    expect(text, isNot(contains('cOMPRESSORS')));
  });

  test('F13: long web endings are kept whole, nothing left in notes', () {
    final c = parse(['Marisol Okafor', 'marisol@ironbridge.example', 'ironbridge.example'], [20, 9, 9]);
    expect(c.website?.value, 'ironbridge.example');
    expect(c.notes, isEmpty);
    expect(parse(['www.acme.company']).website?.value, 'www.acme.company');
    expect(parse(['www.acme.technology']).website?.value, 'www.acme.technology');
  });

  test('F18: headings and slogans are not names; the email picks the person', () {
    expect(parse(['Corporate Office', 'Dick Yisha', 'dyisha@maxpak.example'], [24, 14, 9]).name?.value, 'Dick Yisha');
    expect(parse(['An Emcor Company', 'Fritz Hoffmann'], [24, 14]).name?.value, 'Fritz Hoffmann');
    final wes = parse(
      ['Delivering The Difference', 'Wes Kowalski', 'Sales Leader', 'wes@horsburgh-scott.com'],
      [22, 12, 9, 9],
    );
    expect(wes.name?.value, 'Wes Kowalski');
    final tall = parse(['Travis Dingee', 'Becker Pumps', 'travis.dingee@beckerpumps.com'], [12, 30, 9]);
    expect(tall.name?.value, 'Travis Dingee');
  });

  test('F18: no printed name, a first.last email still gives one to check', () {
    final c = parse(['Delivering The Difference', 'travis.dingee@beckerpumps.com'], [20, 9]);
    expect(c.name?.value, 'Travis Dingee');
    expect(c.name!.needsReview, isTrue);
  });

  test('F19: a garbled email is kept and flagged, not dropped', () {
    final c = parse(['Marisol Okafor', 'marisol@ironbridge,example'], [20, 9]);
    expect(c.emails.single.value, 'marisol@ironbridge.example');
    expect(c.emails.single.needsReview, isTrue);
  });

  test('F21: label prefixes never reach the notes', () {
    final c = parse(
      [
        'Kelley Hollander',
        'P: 330-562-3366 Ext. 1155',
        'F: 330-995-5174',
        'E: kelley.hollander@viking-forge.com',
        'W: www.viking-forge.com',
      ],
      [20, 9, 9, 9, 9],
    );
    expect(c.notes, isEmpty);
    expect(c.faxes.single.value, '+13309955174');
    expect(c.phones.single.extension, '1155');
  });
}
