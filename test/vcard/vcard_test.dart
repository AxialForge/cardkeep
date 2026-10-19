import 'package:card_organizer/core/csv/csv_export.dart';
import 'package:card_organizer/core/vcard/vcard.dart';
import 'package:flutter_test/flutter_test.dart';

const dana = ExportContact(
  first: 'Dana',
  last: 'Reyes',
  company: 'Northwind, Inc',
  title: 'VP Procurement',
  emails: ['dana@northwind.example'],
  phones: [(label: 'M', number: '+1 330 555 0101'), (label: 'O', number: '+1 330 555 0199')],
  notes: 'Met at booth 12;\nwants quote',
);

void main() {
  test('vCard 3.0 escapes and types fields', () {
    final v = writeVCard(dana);
    expect(v, startsWith('BEGIN:VCARD\r\nVERSION:3.0\r\n'));
    expect(v, contains('N:Reyes;Dana;;;'));
    expect(v, contains(r'ORG:Northwind\, Inc'));
    expect(v, contains('TEL;TYPE=CELL:+1 330 555 0101'));
    expect(v, contains('TEL;TYPE=WORK:+1 330 555 0199'));
    expect(v, contains(r'NOTE:Met at booth 12\;\nwants quote'));
    expect(v, endsWith('END:VCARD\r\n'));
  });

  test('vCard 4.0 uses lowercase types', () {
    expect(writeVCard(dana, version: '4.0'), contains('TEL;TYPE=cell:'));
  });

  test('long lines fold at 75', () {
    final v = writeVCard(ExportContact(first: 'A', notes: 'x' * 200));
    for (final line in v.split('\r\n')) {
      expect(line.length, lessThanOrEqualTo(75));
    }
  });

  test('CSV layouts', () {
    final g = writeCsv([dana]);
    expect(g.split('\r\n').first, startsWith('First name,Last name'));
    expect(g, contains('"Northwind, Inc"'));
    final h = writeCsv([dana], layout: CsvLayout.hubspot);
    expect(h, startsWith('First Name,Last Name,Company Name'));
    final s = writeCsv([dana], layout: CsvLayout.salesforce);
    expect(s.split('\r\n')[1], contains('+1 330 555 0101,+1 330 555 0199'));
  });
}
