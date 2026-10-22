/// NFC tap cards (roadmap S14.5, S14.8, S14.9): NDEF parsing in pure Dart so
/// every record type and hostile payload is tested without a phone.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../core/vcard/vcard.dart';
import '../core/vcard/vcard_reader.dart';

/// One NDEF record, independent of the NFC plugin.
class Rec {
  final int tnf; // 1 well-known, 2 MIME, 3 absolute URI, 4 external
  final Uint8List type;
  final Uint8List payload;
  const Rec(this.tnf, this.type, this.payload);

  String get typeText => latin1.decode(type, allowInvalid: true);
}

/// What a tap card carried.
sealed class TapContent {
  const TapContent();
}

class TapContact extends TapContent {
  final ExportContact contact;
  final String? link; // a URL that came with it (Smart Poster or a second record)
  const TapContact(this.contact, {this.link});
}

class TapLink extends TapContent {
  final Uri url;
  final String? title;
  const TapLink(this.url, {this.title});
}

class TapText extends TapContent {
  final String text;
  const TapText(this.text);
}

class TapEmpty extends TapContent {
  const TapEmpty();
}

class TapUnsupported extends TapContent {
  final String why;
  const TapUnsupported(this.why);
}

const maxTagBytes = 8 * 1024; // NTAG216 holds 888 bytes; anything far larger is hostile

/// The URI identifier codes (NFC Forum RTD-URI); 0x01-0x06 are the common ones.
const _uriPrefixes = [
  '',
  'http://www.',
  'https://www.',
  'http://',
  'https://',
  'tel:',
  'mailto:',
  'ftp://anonymous:anonymous@',
  'ftp://ftp.',
  'ftps://',
  'sftp://',
  'smb://',
  'nfs://',
  'ftp://',
  'dav://',
  'news:',
  'telnet://',
  'imap:',
  'rtsp://',
  'urn:',
  'pop:',
  'sip:',
  'sips:',
  'tftp:',
  'btspp://',
  'btl2cap://',
  'btgoep://',
  'tcpobex://',
  'irdaobex://',
  'file://',
  'urn:epc:id:',
  'urn:epc:tag:',
  'urn:epc:pat:',
  'urn:epc:raw:',
  'urn:epc:',
  'urn:nfc:',
];

/// Control characters other than tab/newline are dropped (S14.8).
String clean(String s) => s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');

String? decodeUri(Uint8List p) {
  if (p.isEmpty) return null;
  final prefix = p[0] < _uriPrefixes.length ? _uriPrefixes[p[0]] : '';
  return clean(prefix + utf8.decode(p.sublist(1), allowMalformed: true)).trim();
}

String? decodeText(Uint8List p) {
  if (p.isEmpty) return null;
  final status = p[0];
  final langLen = status & 0x3F;
  if (1 + langLen > p.length) return null;
  final body = p.sublist(1 + langLen);
  final utf16 = status & 0x80 != 0;
  final s = utf16
      ? String.fromCharCodes(
          Uint16List.view(Uint8List.fromList(body.length.isEven ? body : body.sublist(0, body.length - 1)).buffer),
        )
      : utf8.decode(body, allowMalformed: true);
  return clean(s);
}

/// Parses raw NDEF message bytes (also used for Smart Poster contents).
/// Throws [FormatException] on malformed or oversized input.
List<Rec> parseNdefBytes(Uint8List b) {
  if (b.length > maxTagBytes) throw const FormatException('Tag data too large');
  final out = <Rec>[];
  var i = 0;
  while (i < b.length) {
    if (out.length > 32) throw const FormatException('Too many records');
    final h = b[i++];
    final tnf = h & 0x07, sr = h & 0x10 != 0, il = h & 0x08 != 0, me = h & 0x40 != 0;
    if (i >= b.length) throw const FormatException('Truncated header');
    final typeLen = b[i++];
    int payloadLen;
    if (sr) {
      if (i >= b.length) throw const FormatException('Truncated length');
      payloadLen = b[i++];
    } else {
      if (i + 4 > b.length) throw const FormatException('Truncated length');
      payloadLen = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
      i += 4;
    }
    var idLen = 0;
    if (il) {
      if (i >= b.length) throw const FormatException('Truncated id length');
      idLen = b[i++];
    }
    if (payloadLen < 0 || i + typeLen + idLen + payloadLen > b.length) throw const FormatException('Bad length byte');
    final type = Uint8List.sublistView(b, i, i + typeLen);
    i += typeLen + idLen;
    final payload = Uint8List.sublistView(b, i, i + payloadLen);
    i += payloadLen;
    out.add(Rec(tnf, Uint8List.fromList(type), Uint8List.fromList(payload)));
    if (me) break;
  }
  return out;
}

/// What the records mean, best first: a contact beats a link beats text.
TapContent interpret(List<Rec> records) {
  if (records.isEmpty || records.every((r) => r.tnf == 0)) return const TapEmpty();
  ExportContact? contact;
  String? link, title, text;
  for (final r in records) {
    final t = r.typeText.toLowerCase();
    switch (r.tnf) {
      case 2 when t.contains('vcard') || t == 'text/directory' || t == 'text/x-vcard':
        if (r.payload.length > maxTagBytes) return const TapUnsupported('Contact data too large');
        contact ??= readVCards(utf8.decode(r.payload, allowMalformed: true)).firstOrNull;
      case 2 when t.startsWith('text/'):
        text ??= clean(utf8.decode(r.payload, allowMalformed: true));
      case 1 when t == 'u':
        link ??= decodeUri(r.payload);
      case 1 when t == 't':
        text ??= decodeText(r.payload);
      case 1 when t == 'sp':
        // Smart Poster: a nested message with a URI and an optional title.
        try {
          final inner = parseNdefBytes(r.payload);
          for (final x in inner) {
            if (x.tnf == 1 && x.typeText == 'U') link ??= decodeUri(x.payload);
            if (x.tnf == 1 && x.typeText == 'T') title ??= decodeText(x.payload);
          }
        } on FormatException {
          // A broken poster is skipped like any other unreadable record.
        }
      case 3:
        link ??= clean(r.typeText);
    }
  }
  // MECARD or a vCard typed into a text record.
  if (contact == null && text != null) {
    if (text.trimLeft().toUpperCase().startsWith('MECARD:')) contact = readMeCard(text);
    if (text.contains('BEGIN:VCARD')) contact = readVCards(text).firstOrNull;
  }
  if (contact != null) return TapContact(contact, link: link);
  if (link != null) {
    final u = Uri.tryParse(link);
    if (u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty) return TapLink(u, title: title);
    if (u != null && u.scheme == 'tel') return TapText(link);
    return TapUnsupported('Link type not supported: ${u?.scheme ?? 'unknown'}');
  }
  if (text != null && text.trim().isNotEmpty) return TapText(text.trim());
  return const TapUnsupported('Nothing CardKeep can read');
}

/// Rolling-URL cards change counter/MAC parameters on every tap; dropping them
/// lets the same card be recognised again (S14.9).
Uri normaliseUrl(Uri u) {
  const rolling = {'ctr', 'cmac', 'sig', 'e', 'c', 'mac', 'counter', 'uid'};
  final q = Map.of(u.queryParameters)..removeWhere((k, _) => rolling.contains(k.toLowerCase()));
  return Uri(
    scheme: u.scheme.toLowerCase(),
    host: u.host.toLowerCase(),
    path: u.path,
    queryParameters: q.isEmpty ? null : q,
  );
}

/// Same card again within a short time: skipped (S14.3, S14.9).
class TapDebounce {
  final Duration window;
  final _seen = <String, DateTime>{};
  TapDebounce({this.window = const Duration(seconds: 3)});

  bool isRepeat(String key, DateTime now) {
    final last = _seen[key];
    _seen[key] = now;
    return last != null && now.difference(last) < window;
  }
}

/// Key for one tag: its UID plus a hash of what it says (URLs normalised).
String tapKey(Uint8List? uid, TapContent c) {
  final id = uid == null ? '' : uid.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final what = switch (c) {
    TapContact(:final contact) =>
      '${contact.fullName}|${contact.emails.join(',')}|${contact.phones.map((p) => p.number).join(',')}',
    TapLink(:final url) => normaliseUrl(url).toString(),
    TapText(:final text) => text,
    _ => '',
  };
  return '$id#${what.hashCode}';
}
