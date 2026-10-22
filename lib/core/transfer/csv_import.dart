/// CSV import (S13.5): parsing, column guessing and turning rows into
/// contacts. Pure Dart so it tests without a device.
library;

import '../vcard/vcard.dart';

/// What a CSV column can hold.
enum CsvField {
  skip('Skip'),
  first('First name'),
  last('Last name'),
  fullName('Full name'),
  company('Company'),
  title('Title'),
  email('Email'),
  mobile('Mobile phone'),
  phone('Other phone'),
  website('Website'),
  address('Address'),
  notes('Notes');

  final String label;
  const CsvField(this.label);
}

/// RFC 4180 parsing: quoted fields, doubled quotes, CRLF or LF, a BOM.
List<List<String>> parseCsv(String text) {
  final s = text.startsWith('﻿') ? text.substring(1) : text;
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
      continue;
    }
    switch (ch) {
      case '"':
        quoted = true;
      case ',' || ';' when _sep(s) == ch:
        row.add(cell.toString());
        cell.clear();
      case '\r':
        break;
      case '\n':
        row.add(cell.toString());
        cell.clear();
        if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
        row = <String>[];
      default:
        cell.write(ch);
    }
  }
  row.add(cell.toString());
  if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
  return rows;
}

/// Comma, unless the header line clearly uses semicolons (European Excel).
String _sep(String s) {
  final first = s.split('\n').first;
  return ';'.allMatches(first).length > ','.allMatches(first).length ? ';' : ',';
}

/// Guesses each column from its header (generic, Google, Outlook, HubSpot, Salesforce, LinkedIn).
List<CsvField> guessMapping(List<String> headers) {
  CsvField guess(String h) {
    final k = h.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (k.isEmpty) return CsvField.skip;
    if (const {'firstname', 'givenname', 'first'}.contains(k)) return CsvField.first;
    if (const {'lastname', 'familyname', 'surname', 'last'}.contains(k)) return CsvField.last;
    if (const {'name', 'fullname', 'displayname', 'contactname'}.contains(k)) return CsvField.fullName;
    if (k.contains('company') || k.contains('organization') || k.contains('organisation') || k == 'account') {
      return k.contains('title') ? CsvField.title : CsvField.company;
    }
    if (k.contains('title') || k.contains('position') || k.contains('role')) return CsvField.title;
    if (k.contains('email') || k.contains('mail')) return CsvField.email;
    if (k.contains('mobile') || k.contains('cell')) return CsvField.mobile;
    if (k.contains('phone') || k.contains('tel') || k.contains('fax')) return CsvField.phone;
    if (k.contains('website') || k.contains('web') || k.contains('url')) return CsvField.website;
    if (k.contains('address') || k.contains('street')) return CsvField.address;
    if (k.contains('note') || k.contains('description') || k.contains('comment')) return CsvField.notes;
    return CsvField.skip;
  }

  final seen = <CsvField>{};
  return [
    for (final h in headers)
      switch (guess(h)) {
        // Only the first column of a single-value field is used; extras of email/phone are fine.
        final f when f != CsvField.email && f != CsvField.phone && f != CsvField.mobile && !seen.add(f) =>
          CsvField.skip,
        final f => f,
      },
  ];
}

/// Rows (without the header) to contacts with [mapping]. Empty rows are dropped.
List<ExportContact> rowsToContacts(List<List<String>> rows, List<CsvField> mapping) {
  final out = <ExportContact>[];
  for (final r in rows) {
    String? one(CsvField f) {
      for (var i = 0; i < mapping.length && i < r.length; i++) {
        if (mapping[i] == f && r[i].trim().isNotEmpty) return r[i].trim();
      }
      return null;
    }

    List<String> all(CsvField f) => [
      for (var i = 0; i < mapping.length && i < r.length; i++)
        if (mapping[i] == f && r[i].trim().isNotEmpty) r[i].trim(),
    ];
    var first = one(CsvField.first) ?? '';
    var last = one(CsvField.last) ?? '';
    if (first.isEmpty && last.isEmpty) {
      final full = (one(CsvField.fullName) ?? '').split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
      if (full.isNotEmpty) {
        first = full.length > 1 ? full.sublist(0, full.length - 1).join(' ') : full.first;
        last = full.length > 1 ? full.last : '';
      }
    }
    final c = ExportContact(
      first: first,
      last: last,
      company: one(CsvField.company),
      title: one(CsvField.title),
      emails: all(CsvField.email),
      phones: [
        for (final p in all(CsvField.mobile)) (label: 'Mobile', number: p),
        for (final p in all(CsvField.phone)) (label: 'Office', number: p),
      ],
      website: one(CsvField.website),
      address: one(CsvField.address),
      notes: one(CsvField.notes),
    );
    if (c.fullName.isEmpty && c.company == null && c.emails.isEmpty && c.phones.isEmpty) continue;
    out.add(c);
  }
  return out;
}

/// Key for a remembered mapping: the same header row maps the same way next time.
String headerKey(List<String> headers) => headers.map((h) => h.trim().toLowerCase()).join('\u001f');
