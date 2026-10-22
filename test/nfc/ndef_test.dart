import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:card_organizer/nfc/ndef.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds one short NDEF record (SR set).
List<int> rec(int tnf, String type, List<int> payload, {bool mb = true, bool me = true}) => [
  (mb ? 0x80 : 0) | (me ? 0x40 : 0) | 0x10 | tnf,
  type.length,
  payload.length,
  ...latin1.encode(type),
  ...payload,
];

Uint8List bytes(List<int> b) => Uint8List.fromList(b);

void main() {
  test('MIME vCard', () {
    const v = 'BEGIN:VCARD\r\nVERSION:3.0\r\nN:Reyes;Dana;;;\r\nFN:Dana Reyes\r\nORG:Halden\r\nEND:VCARD\r\n';
    final c = interpret(parseNdefBytes(bytes(rec(2, 'text/vcard', utf8.encode(v)))));
    expect(c, isA<TapContact>());
    expect((c as TapContact).contact.fullName, 'Dana Reyes');
  });

  test('URI with prefix codes 0x01 to 0x06', () {
    final expected = {1: 'http://www.x.com', 2: 'https://www.x.com', 3: 'http://x.com', 4: 'https://x.com'};
    for (final e in expected.entries) {
      final c = interpret(parseNdefBytes(bytes(rec(1, 'U', [e.key, ...utf8.encode(e.key <= 2 ? 'x.com' : 'x.com')]))));
      expect((c as TapLink).url.toString(), e.value);
    }
    expect(decodeUri(bytes([5, ...utf8.encode('+13305550142')])), 'tel:+13305550142');
    expect(decodeUri(bytes([6, ...utf8.encode('a@b.com')])), 'mailto:a@b.com');
  });

  test('Smart Poster with a title', () {
    final inner = [
      ...rec(1, 'U', [4, ...utf8.encode('cards.example/dana')], me: false),
      ...rec(1, 'T', [2, ...utf8.encode('en'), ...utf8.encode('Dana Reyes')], mb: false),
    ];
    final c = interpret(parseNdefBytes(bytes(rec(1, 'Sp', inner))));
    expect((c as TapLink).url.toString(), 'https://cards.example/dana');
    expect(c.title, 'Dana Reyes');
  });

  test('Text record, UTF-8 and UTF-16, MECARD inside text', () {
    expect(
      (interpret(
        parseNdefBytes(bytes(rec(1, 'T', [2, ...utf8.encode('en'), ...utf8.encode('Hello')]))),
      ) as TapText).text,
      'Hello',
    );
    final u16 = Uint8List.view(Uint16List.fromList('Hi'.codeUnits).buffer);
    expect(decodeText(bytes([0x80 | 2, ...utf8.encode('en'), ...u16])), 'Hi');
    final me = interpret(
      parseNdefBytes(
        bytes(rec(1, 'T', [2, ...utf8.encode('en'), ...utf8.encode('MECARD:N:Okafor,Sam;TEL:2165550123;;')])),
      ),
    );
    expect((me as TapContact).contact.last, 'Okafor');
  });

  test('multiple records: contact wins and keeps the link', () {
    const v = 'BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Sam Okafor\r\nN:Okafor;Sam;;;\r\nEND:VCARD\r\n';
    final msg = [
      ...rec(1, 'U', [4, ...utf8.encode('brightline.example')], me: false),
      ...rec(2, 'text/x-vcard', utf8.encode(v), mb: false),
    ];
    final c = interpret(parseNdefBytes(bytes(msg))) as TapContact;
    expect(c.contact.fullName, 'Sam Okafor');
    expect(c.link, 'https://brightline.example');
  });

  test('empty and unsupported tags', () {
    expect(interpret(const []), isA<TapEmpty>());
    expect(interpret(parseNdefBytes(bytes([0xD0, 0, 0]))), isA<TapEmpty>(), reason: 'TNF 0 empty record');
    expect(
      interpret(parseNdefBytes(bytes(rec(1, 'U', [0, ...utf8.encode('javascript:alert(1)')])))),
      isA<TapUnsupported>(),
    );
    expect(interpret(parseNdefBytes(bytes(rec(4, 'android.com:pkg', utf8.encode('com.x'))))), isA<TapUnsupported>());
  });

  group('hostile input (S14.8)', () {
    test('bad length bytes and truncation throw FormatException, never crash', () {
      for (final b in [
        [0xD1],
        [0xD1, 1],
        [0xD1, 1, 200, 0x55, 1],
        [0xC1, 1, 0xFF, 0xFF, 0xFF, 0xFF, 0x55],
        [0xD9, 1, 1],
      ]) {
        expect(() => parseNdefBytes(bytes(b)), throwsFormatException, reason: '$b');
      }
    });

    test('oversized data refused', () {
      expect(() => parseNdefBytes(Uint8List(maxTagBytes + 1)), throwsFormatException);
    });

    test('control characters are stripped', () {
      final c = interpret(
        parseNdefBytes(bytes(rec(1, 'T', [2, ...utf8.encode('en'), ...utf8.encode('Dana\x00\x1b[31m Reyes\x07')]))),
      );
      expect((c as TapText).text, 'Dana[31m Reyes');
    });

    test('fuzz: 3000 random byte strings never throw anything but FormatException', () {
      final r = Random(42);
      for (var n = 0; n < 3000; n++) {
        final b = Uint8List.fromList(List.generate(r.nextInt(80), (_) => r.nextInt(256)));
        try {
          interpret(parseNdefBytes(b));
        } on FormatException {
          // expected for most random input
        }
      }
    });
  });

  test('rolling-URL cards normalise to one key; debounce skips repeats', () {
    final a = Uri.parse('https://Tap.Example/c/42?ctr=0001&cmac=AB12&ref=card');
    final b = Uri.parse('https://tap.example/c/42?ctr=0002&cmac=FF00&ref=card');
    expect(normaliseUrl(a), normaliseUrl(b));
    expect(normaliseUrl(a).toString(), 'https://tap.example/c/42?ref=card');
    expect(tapKey(null, TapLink(a)), tapKey(null, TapLink(b)));

    final d = TapDebounce();
    final t = DateTime(2026);
    expect(d.isRepeat('k', t), isFalse);
    expect(d.isRepeat('k', t.add(const Duration(seconds: 2))), isTrue);
    expect(d.isRepeat('k', t.add(const Duration(seconds: 6))), isFalse);
  });
}
