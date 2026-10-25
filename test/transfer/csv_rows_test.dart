import 'package:card_organizer/core/transfer/csv_import.dart';
import 'package:flutter_test/flutter_test.dart';

/// The owner's phone test spreadsheet (0.7.4): a blank line and a phone-only row.
const _file =
    'First Name,Last Name,Company,Email,Phone\r\n'
    'Tessa,Marlow,Pinecrest Supply,tessa@pinecrest.example,330 555 0201\r\n'
    ',,,,\r\n'
    'Noah,Adler,Pinecrest Supply,noah@pinecrest.example,330 555 0202\r\n'
    ',,,,330\r\n';

CsvImport _import(String text) {
  final rows = parseCsv(text, keepBlank: true);
  return csvImport(rows.skip(1).toList(), guessMapping(rows.first));
}

void main() {
  test('row numbers are the spreadsheet rows, blank lines included (header is row 1)', () {
    final r = _import(_file);
    expect(r.contacts.map((c) => c.sourceRow), [2, 4, 5]);
    expect(r.contacts.map((c) => c.first), ['Tessa', 'Noah', '']);
    expect(r.contacts.last.phones.single.number, '330');
    expect(r.problems, isEmpty);
  });

  test('the same file with LF line ends, a BOM and no final newline reads the same', () {
    final lf = '\u{FEFF}${_file.replaceAll('\r\n', '\n').trimRight()}';
    expect(_import(lf).contacts.map((c) => c.sourceRow), [2, 4, 5]);
  });

  test('a row with data only in a column that is not matched is reported at its real row', () {
    const text =
        'First Name,Last Name,Email,Notes\n'
        'Tessa,Marlow,t@x.example,\n'
        ',,,\n' // row 3: blank
        ',,,just a note\n' // row 4: data, nothing usable
        'Noah,Adler,n@x.example,\n';
    final r = _import(text);
    expect(r.contacts.map((c) => c.sourceRow), [2, 5]);
    expect(r.problems.map((p) => p.where), ['Row 4']);
  });

  test('parseCsv still drops blank lines by default and ends cleanly on a final newline', () {
    expect(parseCsv('a,b\n\n1,2\n'), [
      ['a', 'b'],
      ['1', '2'],
    ]);
    expect(parseCsv('a,b\n\n1,2\n', keepBlank: true).length, 3);
  });
}
