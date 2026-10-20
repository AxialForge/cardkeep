import 'package:card_organizer/core/vcard/vcard.dart';
import 'package:card_organizer/core/vcard/vcard_reader.dart';
import 'package:card_organizer/parser/rules.dart';
import 'package:card_organizer/scan/qr_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round trip: what CardKeep writes, it reads back', () {
    const c = ExportContact(
      first: 'Dana',
      last: 'Reyes',
      company: 'Northwind, Inc',
      title: 'VP Procurement',
      emails: ['dana@northwind.example'],
      phones: [(label: 'M', number: '+13305550101'), (label: 'O', number: '+13305550199')],
      website: 'northwind.example',
      address: '1200 Industrial Pkwy, Streetsboro, OH 44241',
      notes: 'Met at booth 12;\nwants quote',
    );
    for (final v in ['3.0', '4.0']) {
      final r = readVCards(writeVCard(c, version: v)).single;
      expect(r.first, 'Dana', reason: v);
      expect(r.last, 'Reyes');
      expect(r.company, 'Northwind, Inc');
      expect(r.title, 'VP Procurement');
      expect(r.phones.map((p) => '${p.label}${p.number}'), ['M+13305550101', 'O+13305550199']);
      expect(r.emails, ['dana@northwind.example']);
      expect(r.notes, 'Met at booth 12;\nwants quote');
    }
  });

  test('vCard 2.1 quoted-printable, folded lines, groups and FN-only names', () {
    const v =
        'BEGIN:VCARD\r\nVERSION:2.1\r\nFN:José María García\r\n'
        'item1.ORG;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:Caf=C3=A9 Ind=\r\nustrial\r\n'
        'TEL;CELL:+34 600 000 000\r\nNOTE:a very long note that\r\n  continues here\r\nEND:VCARD\r\n';
    final r = readVCards(v).single;
    expect(r.first, 'José María');
    expect(r.last, 'García');
    expect(r.company, 'Café Industrial');
    expect(r.phones.single.label, 'M');
    expect(r.notes, 'a very long note that continues here');
  });

  test('several cards in one file; junk lines and non-vCard text', () {
    final two = readVCards('BEGIN:VCARD\nFN:A B\nEND:VCARD\nrandom\nBEGIN:VCARD\nFN:C D\nEND:VCARD\n');
    expect(two.map((c) => c.fullName), ['A B', 'C D']);
    expect(readVCards('hello'), isEmpty);
  });

  test('hostile input: control characters stripped, fields capped, oversize refused', () {
    final r = readVCards('BEGIN:VCARD\nFN:Ev\u0007il \u0000Name\nTITLE:${'x' * 5000}\nEND:VCARD').single;
    expect(r.fullName, 'Evil Name');
    expect(r.title!.length, 500);
    expect(readVCards('BEGIN:VCARD\nNOTE:${'y' * 9000}\nEND:VCARD', maxBytes: maxTagPayload), isEmpty);
  });

  test('MECARD', () {
    final r = readMeCard(
      r'MECARD:N:Okafor,Sam;TEL:+12165550123;EMAIL:sam@brightline.io;URL:https\://brightline.io;ORG:Brightline;;',
    )!;
    expect(r.fullName, 'Sam Okafor');
    expect(r.company, 'Brightline');
    expect(r.website, 'https://brightline.io');
  });

  group('QR content', () {
    test('classifies contact, link and other codes', () {
      expect(QrContent.classify('BEGIN:VCARD\nFN:A B\nEND:VCARD').kind, QrKind.contact);
      expect(QrContent.classify('MECARD:N:B,A;;').kind, QrKind.contact);
      expect(QrContent.classify('https://popl.co/u/abc').kind, QrKind.link);
      expect(QrContent.classify('WIFI:S:office;T:WPA;P:secret;;').kind, QrKind.other);
      expect(QrContent.classify('just text').kind, QrKind.other);
    });

    test('link checks flag shorteners, punycode, http, IPs and @ tricks', () {
      expect(LinkCheck.of(Uri.parse('https://brightline.io/sam')).warnings, isEmpty);
      expect(LinkCheck.of(Uri.parse('https://bit.ly/x')).warnings.single, contains('shortener'));
      expect(LinkCheck.of(Uri.parse('https://xn--pple-43d.com')).warnings.single, contains('punycode'));
      expect(LinkCheck.of(Uri.parse('http://example.com')).warnings.single, contains('https'));
      expect(LinkCheck.of(Uri.parse('https://10.0.0.1/a')).warnings.single, contains('IP'));
      expect(LinkCheck.of(Uri.parse('https://paypal.com@evil.example')).warnings, isNotEmpty);
    });

    test('QR wins, OCR fills gaps, disagreements are flagged', () {
      final qr = QrContent.classify('MECARD:N:Okafor,Sam;TEL:+12165550123;EMAIL:sam@brightline.io;ORG:Brightline;;')
          .toParsed()!;
      final ocr = ParsedCard()
        ..name = const ParsedField('Sam Okafor', 0.9)
        ..title = const ParsedField('Head of Sales', 0.85)
        ..company = const ParsedField('Brightlne', 0.6);
      ocr.phones
        ..add(const ParsedPhone('+12165550123', 0.98, 'mobile'))
        ..add(const ParsedPhone('+12165550199', 0.98, 'office'));
      final (m, conflicts) = mergeStructured(qr, ocr);
      expect(m.name!.value, 'Sam Okafor');
      expect(m.company!.value, 'Brightline'); // structured wins
      expect(m.title!.value, 'Head of Sales'); // gap filled from OCR
      expect(m.phones.map((p) => p.value), ['+12165550123', '+12165550199']);
      expect(conflicts, {'company'});
    });
  });
}
