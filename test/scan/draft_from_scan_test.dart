import 'package:card_organizer/parser/ocr.dart';
import 'package:card_organizer/parser/rules.dart';
import 'package:card_organizer/scan/scan_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ParsedCard card(List<String> lines, List<double> heights) => parseCard(OcrPage.fromText(lines, heights: heights));

  test('front fills the form; back adds what the front lacks', () {
    final front = card(
      ['HALDEN TOOLING GROUP', 'Priya Nambiar', 'Director of Procurement', 'M 330-555-0142', 'p.nambiar@haldentooling.com'],
      [14, 22, 11, 9, 9],
    );
    final back = card(['4200 Industrial Pkwy', 'Akron, OH 44311', 'T 330-555-0188'], [9, 9, 9]);
    final d = draftFromScan(front, back);
    expect(d.first, 'Priya');
    expect(d.last, 'Nambiar');
    expect(d.company, 'HALDEN TOOLING GROUP');
    expect(d.title, 'Director of Procurement');
    expect(d.address, '4200 Industrial Pkwy, Akron, OH 44311');
    expect(d.phones.map((p) => '${p.label} ${p.value}'), ['Mobile +13305550142', 'Office +13305550188']);
    expect(d.emails, ['p.nambiar@haldentooling.com']);
  });

  test('empty scan still gives one blank phone and email row', () {
    final d = draftFromScan(null);
    expect(d.phones.single.value, '');
    expect(d.emails.single, '');
  });

  test('uncertain fields are reported for amber marking', () {
    final c = parseCard(OcrPage([const OcrLine('Ana Lima', height: 20, confidence: 0.4), const OcrLine('ana@acme.com', height: 9)]));
    expect(uncertainFields(c), contains('name'));
  });
}
