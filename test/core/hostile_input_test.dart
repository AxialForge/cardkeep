import 'package:card_organizer/core/followups/reminders.dart';
import 'package:card_organizer/core/links/link_launcher.dart';
import 'package:card_organizer/core/transfer/csv_import.dart';
import 'package:card_organizer/parser/ocr.dart';
import 'package:card_organizer/parser/rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hostile or oversized input (audit MOB-SEC-0100, 0101, 0103, MOB-REL-0007).
void main() {
  test('a 5000-row CSV parses in well under a second (MOB-SEC-0100)', () {
    final csv = StringBuffer('First name,Last name,Company,Email,Mobile phone\n');
    for (var i = 0; i < 5000; i++) {
      csv.write('Dana$i,Reyes,"Halden, Tooling",dana$i@halden.example,330 555 ${i % 10000}\n');
    }
    final sw = Stopwatch()..start();
    final rows = parseCsv(csv.toString());
    expect(sw.elapsedMilliseconds, lessThan(1000));
    expect(rows.length, 5001);
    expect(rows[1][2], 'Halden, Tooling');
  });

  test('semicolon CSV is still detected from the header', () {
    expect(parseCsv('a;b\n1;2\n')[1], ['1', '2']);
  });

  test('very long OCR lines parse quickly (MOB-SEC-0101)', () {
    final sw = Stopwatch()..start();
    parseCard(OcrPage.fromText(['1' * 50000, 'a.' * 25000, 'x@' * 25000, 'Dana Reyes']));
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });

  test('malformed or non-web addresses never throw and never open (MOB-SEC-0103)', () async {
    final opened = <Uri>[];
    final l = LinkLauncher((u) async {
      opened.add(u);
      return true;
    });
    for (final bad in ['javascript:alert(1)', 'https://[bad', 'http://', '   ']) {
      expect(LinkLauncher.webUri(bad), isNull, reason: bad);
      expect(await l.web(bad), isFalse, reason: bad);
    }
    expect(opened, isEmpty);
    expect(LinkLauncher.webUri('halden.example/team').toString(), 'https://halden.example/team');
    expect(LinkLauncher.webUri('HTTP://halden.example')!.scheme, 'http');
  });

  test('reminder ids are stable and spread (MOB-REL-0007)', () {
    expect(Reminders.idFor('abc'), 0x1a47e90b, reason: 'FNV-1a, the same on every launch');
    final ids = {for (var i = 0; i < 1000; i++) Reminders.idFor('person-$i')};
    expect(ids.length, greaterThan(995));
    expect(ids.every((i) => i >= 0 && i < 0x40000000), isTrue);
  });
}
