/// Plain export model, independent of drift so writers test without a DB.
class ExportContact {
  final String first;
  final String last;
  final String? company;
  final String? title;
  final List<String> emails;
  final List<({String label, String number})> phones;
  final String? website;
  final String? address;
  final String? notes;

  const ExportContact({
    this.first = '',
    this.last = '',
    this.company,
    this.title,
    this.emails = const [],
    this.phones = const [],
    this.website,
    this.address,
    this.notes,
  });

  String get fullName => [first, last].where((s) => s.isNotEmpty).join(' ');
}

String _esc(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll('\n', r'\n')
    .replaceAll(',', r'\,')
    .replaceAll(';', r'\;');

/// vCard 3.0 (default) or 4.0, CRLF line endings, lines folded at 75 octets.
String writeVCard(ExportContact c, {String version = '3.0'}) {
  final v4 = version == '4.0';
  final lines = <String>[
    'BEGIN:VCARD',
    'VERSION:$version',
    'N:${_esc(c.last)};${_esc(c.first)};;;',
    'FN:${_esc(c.fullName)}',
    if (c.company != null && c.company!.isNotEmpty) 'ORG:${_esc(c.company!)}',
    if (c.title != null && c.title!.isNotEmpty) 'TITLE:${_esc(c.title!)}',
    for (final e in c.emails)
      v4 ? 'EMAIL;TYPE=work:${_esc(e)}' : 'EMAIL;TYPE=INTERNET,WORK:${_esc(e)}',
    for (final p in c.phones)
      v4
          ? 'TEL;TYPE=${_telType(p.label).toLowerCase()}:${_esc(p.number)}'
          : 'TEL;TYPE=${_telType(p.label)}:${_esc(p.number)}',
    if (c.website != null && c.website!.isNotEmpty) 'URL:${c.website}',
    if (c.address != null && c.address!.isNotEmpty)
      'ADR;TYPE=${v4 ? 'work' : 'WORK'}:;;${_esc(c.address!)};;;;',
    if (c.notes != null && c.notes!.isNotEmpty) 'NOTE:${_esc(c.notes!)}',
    'END:VCARD',
  ];
  return '${lines.map(_fold).join('\r\n')}\r\n';
}

String writeVCards(Iterable<ExportContact> cs, {String version = '3.0'}) =>
    cs.map((c) => writeVCard(c, version: version)).join();

String _telType(String label) {
  final l = label.toLowerCase();
  if (l.startsWith('m') || l.contains('cell')) return 'CELL';
  return 'WORK';
}

String _fold(String line) {
  final units = line.runes.toList();
  if (units.length <= 75) return line;
  final out = StringBuffer();
  for (var i = 0; i < units.length; i += 74) {
    final end = (i + 74).clamp(0, units.length);
    if (i > 0) out.write('\r\n ');
    out.write(String.fromCharCodes(units.sublist(i, end)));
  }
  return out.toString();
}
