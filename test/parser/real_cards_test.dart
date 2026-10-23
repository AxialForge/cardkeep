// The owner's own cards that read badly in 0.7.0 (2026-10-23): line patterns as
// printed on the card.
import 'package:card_organizer/parser/ocr.dart';
import 'package:card_organizer/parser/place.dart';
import 'package:card_organizer/parser/rules.dart';
import 'package:card_organizer/scan/scan_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

ParsedCard parse(List<String> lines, [List<double>? heights]) => parseCard(OcrPage.fromText(lines, heights: heights));

void main() {
  group('Nordonia Dental Group', () {
    final card = parse(
      [
        'NORDONIA',
        'Dental Group',
        'Dr. Philip J Znidarsic DDS',
        '98 W. Aurora Rd',
        'Northfield, OH 44067',
        'dr.z@nordoniadental.com',
        '330-467-6466',
        'www.nordoniadental.com',
      ],
      [30, 26, 9, 9, 9, 9, 9, 9],
    );

    test('name with Dr. in front and DDS behind, middle initial without a dot', () {
      expect(card.name?.value, 'Philip J Znidarsic');
      expect(card.suffix?.value, 'Dr., DDS');
      final d = draftFromScan(card);
      expect([d.first, d.middle, d.last], ['Philip', 'J', 'Znidarsic']);
    });

    test('company printed over two lines is joined', () {
      expect(card.company?.value, 'Nordonia Dental Group');
    });

    test('contact details', () {
      expect(card.address?.value, '98 W. Aurora Rd, Northfield, OH 44067');
      expect(card.emails.single.value, 'dr.z@nordoniadental.com');
      expect(card.phones.single.value, '+13304676466');
      expect(card.website?.value, 'www.nordoniadental.com');
    });

    test('a person, not a place', () {
      expect(guessPlace(card), isNull);
    });
  });

  group('Total Party Kill Games', () {
    final front = parse(
      [
        'BRIAN BERG, DIRECTOR OF OPERATIONS',
        'BRIAN@TOTALPARTYKILL.GAMES',
        'CELL: 319.429.1059',
        'SEE OUR FULL HOARD OF GAMING PRODUCTS AT:',
        'WWW.TOTALPARTYKILL.GAMES',
        'MAKERS OF KILLER DARK FANTASY ROLE-PLAYING GAME SOURCEBOOKS, ADVENTURES, DICE, SOCIAL CARD GAMES, SPELL CARDS AND MORE!',
      ],
      [9, 9, 9, 10, 24, 10],
    );
    final back = parse(['FREE DOWNLOADS!', 'GET FREE D&D CHARACTER SHEETS, PDF SOURCEBOOKS AND MORE!'], [24, 9]);

    test('"NAME, TITLE" on one line gives both', () {
      expect(front.name?.value, 'Brian Berg');
      expect(front.title?.value, 'Director of Operations');
    });

    test('mobile, email and website; never "Www..." as the company', () {
      expect(front.phones.single.label, 'mobile');
      expect(front.phones.single.value, '+13194291059');
      expect(front.emails.single.value, 'brian@totalpartykill.games');
      expect(front.website?.value, 'www.totalpartykill.games');
      expect(front.company?.value.toLowerCase(), isNot(startsWith('www')));
      expect(front.company?.value, 'Totalpartykill');
      expect(front.company!.needsReview, isTrue);
    });

    test('slogans go to notes, and the card stays a person', () {
      expect(front.notes, hasLength(2));
      expect(guessPlace(front, back), isNull);
    });

    test('the back adds notes only', () {
      expect(back.name, isNull);
      expect(back.company, isNull);
      expect(back.title, isNull);
      expect(back.notes, hasLength(2));
      final d = draftFromScan(front, back);
      expect(d.first, 'Brian');
      expect(d.title, 'Director of Operations');
    });
  });

  test('a sideways reading loses to the upright one when choosing a turn', () {
    const sideways = OcrPage([
      OcrLine('BRIAN BERG, DIRECTOR OF OPERATIONS', left: 800, top: 100, width: 30, height: 600),
      OcrLine('WWW.TOTALPARTYKILL.GAMES', left: 600, top: 100, width: 60, height: 900),
    ]);
    const upright = OcrPage([
      OcrLine('BRIAN BERG, DIRECTOR OF OPERATIONS', left: 100, top: 100, width: 600, height: 30),
      OcrLine('WWW.TOTALPARTYKILL.GAMES', left: 100, top: 300, width: 900, height: 60),
    ]);
    expect(bestRotation({0: turnScore(sideways), 90: turnScore(upright), 270: turnScore(sideways)}), 90);
    expect(bestRotation({0: turnScore(upright), 90: turnScore(sideways)}), 0);
  });

  test('other honorifics and credentials', () {
    expect(parse(['Prof. Ana M. Ruiz PhD']).name?.value, 'Ana M. Ruiz');
    expect(parse(['Mrs. Ana Ruiz']).suffix?.value, 'Mrs.');
    expect(parse(['Jane Doe, P.E.']).suffix?.value, 'P.E.');
  });

  test('joinsCompany: only a short logo word as big as the company line', () {
    expect(joinsCompany('NORDONIA', 30, 26, 'nordoniadental'), isTrue);
    expect(joinsCompany('Welcome to', 30, 26, null), isFalse);
    expect(joinsCompany('SALES MANAGER', 30, 26, null), isFalse);
    expect(joinsCompany('ACME', 9, 26, null), isFalse);
  });
}
