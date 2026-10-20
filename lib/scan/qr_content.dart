import '../core/vcard/vcard.dart';
import '../core/vcard/vcard_reader.dart';
import '../parser/rules.dart';

enum QrKind { contact, link, other }

/// What a QR code on a card holds (deep dive §2.5).
class QrContent {
  final QrKind kind;
  final String raw;
  final ExportContact? contact; // kind == contact
  final Uri? url; // kind == link
  const QrContent(this.kind, this.raw, {this.contact, this.url});

  static QrContent classify(String raw) {
    final t = raw.trim();
    final upper = t.toUpperCase();
    if (upper.startsWith('BEGIN:VCARD')) {
      final c = readVCards(t, maxBytes: maxTagPayload);
      if (c.isNotEmpty) return QrContent(QrKind.contact, t, contact: c.first);
    }
    if (upper.startsWith('MECARD:')) {
      final c = readMeCard(t);
      if (c != null) return QrContent(QrKind.contact, t, contact: c);
    }
    final u = Uri.tryParse(t);
    if (u != null && (u.scheme == 'https' || u.scheme == 'http') && u.host.isNotEmpty) {
      return QrContent(QrKind.link, t, url: u);
    }
    // Wi-Fi, SMS, app-store and plain-text codes are ignored (§2.5).
    return QrContent(QrKind.other, t);
  }

  /// The QR contact as parser output with full confidence, so it merges with OCR.
  ParsedCard? toParsed() {
    final c = contact;
    if (c == null) return null;
    final p = ParsedCard();
    if (c.fullName.isNotEmpty) p.name = ParsedField(c.fullName, 1);
    if (c.title != null) p.title = ParsedField(c.title!, 1);
    if (c.company != null) p.company = ParsedField(c.company!, 1);
    if (c.website != null) p.website = ParsedField(c.website!, 1);
    if (c.address != null) p.address = ParsedField(c.address!, 1);
    p.emails.addAll(c.emails.map((e) => ParsedField(e, 1)));
    for (final ph in c.phones) {
      if (ph.label == 'F') {
        p.notes.add('Fax: ${ph.number}');
      } else {
        p.phones.add(ParsedPhone(ph.number, 1, ph.label == 'M' ? 'mobile' : 'office'));
      }
    }
    if (c.notes != null) p.notes.add(c.notes!);
    return p;
  }
}

/// How suspicious a link looks before "Open" (deep dive §3.7).
class LinkCheck {
  final String host;
  final List<String> warnings;
  const LinkCheck(this.host, this.warnings);

  static const _shorteners = {
    'bit.ly',
    'tinyurl.com',
    't.co',
    'goo.gl',
    'ow.ly',
    'is.gd',
    'buff.ly',
    'rebrand.ly',
    'cutt.ly',
    'shorturl.at',
    'tiny.cc',
    'lnkd.in',
    'rb.gy',
    'qrco.de',
    'qr.codes',
    's.id',
  };

  static LinkCheck of(Uri u) {
    final host = u.host.toLowerCase();
    return LinkCheck(host, [
      if (u.scheme != 'https') 'Not a secure (https) link',
      if (host.split('.').any((p) => p.startsWith('xn--'))) 'Uses look-alike characters (punycode)',
      if (RegExp(r'[^\x00-\x7F]').hasMatch(host)) 'Contains non-Latin characters',
      if (_shorteners.contains(host)) 'A link shortener: the real site is hidden',
      if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) 'A bare IP address, not a site name',
      if (u.userInfo.isNotEmpty) 'Has text before "@" that can disguise the real site',
    ]);
  }
}

/// Merges a structured source (QR vCard) with OCR: structured wins, OCR fills
/// gaps, and fields where both have a value that disagrees are returned so the
/// form can mark them amber (spec §6, deep dive §1).
(ParsedCard, Set<String>) mergeStructured(ParsedCard structured, ParsedCard? ocr) {
  if (ocr == null) return (structured, const {});
  String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final conflicts = <String>{};
  ParsedField? pick(String key, ParsedField? a, ParsedField? b) {
    if (a != null && b != null && norm(a.value) != norm(b.value)) conflicts.add(key);
    return a ?? b;
  }

  final m = ParsedCard()
    ..name = pick('name', structured.name, ocr.name)
    ..suffix = structured.suffix ?? ocr.suffix
    ..title = pick('title', structured.title, ocr.title)
    ..company = pick('company', structured.company, ocr.company)
    ..website = pick('website', structured.website, ocr.website)
    ..address = pick('address', structured.address, ocr.address);
  m.emails.addAll(structured.emails);
  for (final e in ocr.emails) {
    if (m.emails.every((x) => norm(x.value) != norm(e.value))) m.emails.add(e);
  }
  m.phones.addAll(structured.phones);
  final digits = {for (final p in structured.phones) p.value.replaceAll(RegExp(r'\D'), '')};
  for (final p in ocr.phones) {
    final d = p.value.replaceAll(RegExp(r'\D'), '');
    if (!digits.any((x) => x.endsWith(d) || d.endsWith(x))) m.phones.add(p);
  }
  m.notes
    ..addAll(structured.notes)
    ..addAll(ocr.notes.where((n) => !structured.notes.contains(n)));
  return (m, conflicts);
}
