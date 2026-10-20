import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:card_organizer/scan/scan_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real ML Kit output (emulator, synthetic card): two labelled numbers on one
/// line. Regression for the label lookup reading shifted text (S7 bug).
void main() {
  test('two labelled phones on one line both keep their labels; the card is clean', () {
    final j = jsonDecode(File('test/fixtures/mlkit_dana_two_phones.json').readAsStringSync()) as Map<String, Object?>;
    final s = ScannedSide.fromJson('x', Uint8List(0), j);
    final p = s.parsed!;
    expect(p.phones.map((x) => '${x.label} ${x.value}'), ['mobile +13305550101', 'office +13305550199']);
    expect(p.phones.every((x) => x.confidence >= 0.85), isTrue);
    expect(isCleanCard(s), isTrue);
  });
}
