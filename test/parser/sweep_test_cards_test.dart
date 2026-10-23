// Lines as ML Kit read them in the first Sweep scan test on the owner's
// S25 Ultra (2026-10-23).
import 'package:card_organizer/parser/ocr.dart';
import 'package:card_organizer/parser/rules.dart';
import 'package:flutter_test/flutter_test.dart';

ParsedCard parse(List<String> lines, [List<double>? heights]) => parseCard(OcrPage.fromText(lines, heights: heights));

void main() {
  test('a slogan is never the company (LUNAR card)', () {
    final card = parse(
      [
        'LUNAR',
        'Proudly Serving the Aerospace Industry',
        'Fritz Hoffmann',
        'Sales Engineer',
        'fritz@lunar.example',
        '440 555 0109',
      ],
      [26, 9, 14, 10, 9, 9],
    );
    expect(card.company?.value, isNot(contains('Proudly')));
    expect(card.company?.value, 'Lunar');
    expect(card.name?.value, 'Fritz Hoffmann');
  });

  test('"ENPRESS LuC" reads as ENPRESS LLC', () {
    final card = parse(
      ['ENPRESS LuC', 'Justin Fink', 'Product Engineer', 'jfink@enpress.com', '440 510 0108'],
      [24, 14, 10, 9, 9],
    );
    expect(card.company?.value, 'Enpress LLC');
  });

  test('LLC look-alikes after a company name', () {
    for (final v in ['LuC', 'LIC', 'L1C', 'L.L.C', 'L.L.C.', 'LLG', 'LLC']) {
      expect(normaliseLlc('Enpress $v'), 'Enpress LLC', reason: v);
    }
    expect(normaliseLlc('LIC'), 'LIC', reason: 'a lone word is left alone');
    expect(normaliseLlc('Lunar Lic Holdings'), 'Lunar Lic Holdings', reason: 'only the last word');
  });
}
