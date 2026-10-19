// Runs the parser over the real-card set in test/cards (spec §12).
//
// Per card:  <id>.jpg        the photo (kept for re-OCR, not read here)
//            <id>.ocr.json   OCR output captured on a device (OcrPage JSON)
//            <id>.json       ground truth: {"region":"US","fields":{...}}
// Field keys: name, title, company, email, mobile, office, website, address.
// Targets are enforced once the set has 40 cards; before that it only reports.
import 'dart:convert';
import 'dart:io';

import 'package:card_organizer/parser/ocr.dart';
import 'package:card_organizer/parser/rules.dart';
import 'package:flutter_test/flutter_test.dart';

const targets = {
  'email': .98, 'mobile': .98, 'office': .98,
  'name': .92, 'company': .90, 'title': .85,
};
const fullSetSize = 40;

String _norm(String key, String? v) {
  if (v == null) return '';
  if (key == 'mobile' || key == 'office') return v.replaceAll(RegExp(r'\D'), '');
  return v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9à-ÿ]'), '');
}

void main() {
  final dir = Directory('test/cards');
  final truths = dir.existsSync()
      ? (dir.listSync().whereType<File>()
          .where((f) => f.path.endsWith('.json') &&
              !f.path.endsWith('.ocr.json') &&
              !f.path.endsWith('.draft.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];

  test('ground-truth card set', () {
    if (truths.isEmpty) {
      markTestSkipped('No cards in test/cards yet');
      return;
    }
    final hits = <String, int>{}, totals = <String, int>{};
    final misses = <String>[];
    for (final t in truths) {
      final id = t.uri.pathSegments.last.replaceAll('.json', '');
      final ocrFile = File('${dir.path}/$id.ocr.json');
      if (!ocrFile.existsSync()) {
        misses.add('$id: no .ocr.json yet');
        continue;
      }
      final truth = jsonDecode(t.readAsStringSync()) as Map<String, dynamic>;
      final expected = (truth['fields'] as Map).cast<String, String?>();
      final got = parseCard(
        OcrPage.fromJson(jsonDecode(ocrFile.readAsStringSync()) as Map<String, dynamic>),
        region: truth['region'] as String? ?? 'US',
      ).toFields();
      for (final e in expected.entries) {
        totals[e.key] = (totals[e.key] ?? 0) + 1;
        if (_norm(e.key, e.value) == _norm(e.key, got[e.key])) {
          hits[e.key] = (hits[e.key] ?? 0) + 1;
        } else {
          misses.add('$id.${e.key}: want "${e.value}" got "${got[e.key]}"');
        }
      }
    }
    final report = StringBuffer('Cards: ${truths.length}\n');
    final failing = <String>[];
    for (final k in totals.keys) {
      final rate = (hits[k] ?? 0) / totals[k]!;
      report.writeln('  $k: ${(rate * 100).toStringAsFixed(1)}% (${hits[k] ?? 0}/${totals[k]})');
      if (targets[k] != null && rate < targets[k]!) failing.add(k);
    }
    if (misses.isNotEmpty) report.writeln('Misses:\n  ${misses.join('\n  ')}');
    // ignore: avoid_print
    print(report);
    if (truths.length >= fullSetSize) {
      expect(failing, isEmpty, reason: 'Below target: $failing');
    }
  });
}
