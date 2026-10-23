import 'dart:convert';

import 'vcard.dart';

/// Size caps (deep dive §3.7): payloads from tags and QR codes are untrusted.
const maxTagPayload = 8 * 1024;
const maxFilePayload = 1024 * 1024;
const _maxField = 500;

/// Reads vCard 2.1 / 3.0 / 4.0 text into contacts. Tolerant: unknown
/// properties are ignored, broken lines skipped, control characters stripped,
/// every value capped. Returns an empty list for non-vCard text.
List<ExportContact> readVCards(String text, {int maxBytes = maxFilePayload}) {
  if (utf8.encode(text).length > maxBytes) return const [];
  // Unfold: CRLF/LF followed by a space or tab continues the previous line.
  final unfolded = text.replaceAll(RegExp(r'\r?\n[ \t]'), '');
  final lines = unfolded.split(RegExp(r'\r?\n'));
  final out = <ExportContact>[];
  _Builder? b;
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    // vCard 2.1 quoted-printable soft line breaks end with '='.
    while (line.toUpperCase().contains('QUOTED-PRINTABLE') && line.endsWith('=') && i + 1 < lines.length) {
      line = line.substring(0, line.length - 1) + lines[++i];
    }
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    final head = line.substring(0, colon);
    var value = line.substring(colon + 1);
    final parts = head.split(';');
    final name = parts.first.split('.').last.toUpperCase(); // drop item1. groups
    final params = parts.skip(1).map((p) => p.toUpperCase()).toList();
    if (name == 'BEGIN' && value.trim().toUpperCase() == 'VCARD') {
      b = _Builder();
      continue;
    }
    if (name == 'END' && value.trim().toUpperCase() == 'VCARD') {
      if (b != null) out.add(b.build());
      b = null;
      continue;
    }
    final card = b;
    if (card == null) continue;
    if (params.any((p) => p.contains('QUOTED-PRINTABLE'))) value = _decodeQp(value, params);
    switch (name) {
      case 'N':
        final n = _split(value, ';');
        card.last = _clean(n.elementAtOrNull(0));
        card.first = _clean(
          [n.elementAtOrNull(1), n.elementAtOrNull(2)].whereType<String>().where((s) => s.isNotEmpty).join(' '),
        );
      case 'FN':
        card.fn = _clean(_unescape(value));
      case 'ORG':
        card.company = _clean(_split(value, ';').where((s) => s.isNotEmpty).join(', '));
      case 'TITLE':
        card.title = _clean(_unescape(value));
      case 'TEL':
        final t = _clean(_unescape(value)).replaceFirst(RegExp(r'^tel:', caseSensitive: false), '');
        if (t.isNotEmpty) card.phones.add((label: _telLabel(params), number: t));
      case 'EMAIL':
        final e = _clean(_unescape(value)).replaceFirst(RegExp(r'^mailto:', caseSensitive: false), '');
        if (e.contains('@')) card.emails.add(e.toLowerCase());
      case 'URL':
        card.website ??= _clean(_unescape(value));
      case 'ADR':
        final a = _split(value, ';').map((s) => s.trim()).where((s) => s.isNotEmpty).join(', ');
        card.address ??= _clean(a);
      case 'NOTE':
        card.notes = _clean(_unescape(value), max: 2000);
      case 'KIND':
        if (value.trim().toLowerCase() == 'org') card.isOrg = true;
      case 'X-ABSHOWAS':
        if (value.trim().toUpperCase() == 'COMPANY') card.isOrg = true;
      case 'X-CARDKEEP-HOURS':
        card.hours = _clean(_unescape(value));
    }
  }
  return out;
}

/// MECARD (QR codes): `MECARD:N:Reyes,Dana;TEL:+1330…;EMAIL:…;URL:…;ADR:…;ORG:…;NOTE:…;;`
ExportContact? readMeCard(String text) {
  final t = text.trim();
  if (!t.toUpperCase().startsWith('MECARD:') || utf8.encode(t).length > maxTagPayload) return null;
  final b = _Builder();
  for (final field in _split(t.substring(7), ';')) {
    final colon = field.indexOf(':');
    if (colon <= 0) continue;
    final key = field.substring(0, colon).toUpperCase();
    final value = _clean(field.substring(colon + 1).replaceAll(r'\:', ':').replaceAll(r'\,', ','));
    switch (key) {
      case 'N':
        final n = value.split(',');
        b.last = n.first.trim();
        b.first = n.length > 1 ? n[1].trim() : '';
      case 'TEL':
        b.phones.add((label: 'M', number: value));
      case 'EMAIL':
        b.emails.add(value.toLowerCase());
      case 'URL':
        b.website ??= value;
      case 'ADR':
        b.address ??= value;
      case 'ORG':
        b.company = value;
      case 'TITLE':
        b.title = value;
      case 'NOTE':
        b.notes = value;
    }
  }
  return b.build();
}

class _Builder {
  String first = '', last = '', fn = '';
  String? company, title, website, address, notes, hours;
  bool isOrg = false;
  final phones = <({String label, String number})>[];
  final emails = <String>[];

  ExportContact build() {
    var f = first, l = last;
    // A business: FN is its name, never split into first and last.
    final org = isOrg && ((company ?? '').isNotEmpty || fn.isNotEmpty);
    if (org) {
      company = (company ?? '').isEmpty ? fn : company;
      f = '';
      l = '';
    } else if (f.isEmpty && l.isEmpty && fn.isNotEmpty) {
      final parts = fn.split(RegExp(r'\s+'));
      f = parts.length > 1 ? parts.sublist(0, parts.length - 1).join(' ') : parts.first;
      l = parts.length > 1 ? parts.last : '';
    }
    return ExportContact(
      first: f,
      last: l,
      company: company?.isEmpty ?? true ? null : company,
      title: title?.isEmpty ?? true ? null : title,
      emails: emails,
      phones: phones,
      website: website?.isEmpty ?? true ? null : website,
      address: address?.isEmpty ?? true ? null : address,
      notes: notes?.isEmpty ?? true ? null : notes,
      isOrg: org,
      hours: hours?.isEmpty ?? true ? null : hours,
    );
  }
}

String _telLabel(List<String> params) {
  final p = params.join(';');
  if (p.contains('CELL') || p.contains('MOBILE')) return 'M';
  if (p.contains('FAX')) return 'F';
  return 'O';
}

/// Splits on [sep] but not on backslash-escaped separators.
List<String> _split(String s, String sep) {
  final out = <String>[];
  final cur = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == r'\' && i + 1 < s.length) {
      cur.write(c + s[++i]);
    } else if (c == sep) {
      out.add(_unescape(cur.toString()));
      cur.clear();
    } else {
      cur.write(c);
    }
  }
  out.add(_unescape(cur.toString()));
  return out;
}

String _unescape(String s) => s
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\N', '\n')
    .replaceAll(r'\,', ',')
    .replaceAll(r'\;', ';')
    .replaceAll(r'\:', ':')
    .replaceAll(r'\\', r'\');

/// Control characters out (except newline in notes), whitespace trimmed, length capped.
String _clean(String? s, {int max = _maxField}) {
  if (s == null) return '';
  final t = s.replaceAll(RegExp(r'[\x00-\x09\x0B-\x1F\x7F]'), '').trim();
  return t.length > max ? t.substring(0, max) : t;
}

String _decodeQp(String v, List<String> params) {
  final bytes = <int>[];
  for (var i = 0; i < v.length; i++) {
    final n = v[i] == '=' && i + 2 < v.length ? int.tryParse(v.substring(i + 1, i + 3), radix: 16) : null;
    if (n != null) {
      bytes.add(n);
      i += 2;
    } else {
      bytes.addAll(utf8.encode(v[i]));
    }
  }
  final latin = params.any((p) => p.contains('CHARSET=ISO-8859-1'));
  return latin ? latin1.decode(bytes, allowInvalid: true) : utf8.decode(bytes, allowMalformed: true);
}
