import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import 'ocr.dart';

/// Fields below this are flagged amber on the Review screen (spec §6 rule 7).
const reviewThreshold = 0.7;

class ParsedField {
  final String value;
  final double confidence;
  const ParsedField(this.value, this.confidence);
  bool get needsReview => confidence < reviewThreshold;
  @override
  String toString() => '$value (${confidence.toStringAsFixed(2)})';
}

class ParsedPhone extends ParsedField {
  /// mobile | office | fax
  final String label;

  /// Extension digits ("Ext. 112" -> "112"), '' when none.
  final String extension;
  const ParsedPhone(super.value, super.confidence, this.label, {this.extension = ''});
}

/// Other card text with a recognised meaning (S10b.5).
class ParsedExtra {
  final String label, value;
  const ParsedExtra(this.label, this.value);
}

class ParsedCard {
  ParsedField? name, suffix, title, company, address, website;
  final emails = <ParsedField>[];
  final phones = <ParsedPhone>[]; // mobile and office
  final faxes = <ParsedPhone>[];
  final extras = <ParsedExtra>[];
  final notes = <String>[];

  bool get needsReview =>
      [name, title, company, address, website, ...emails, ...phones].any((f) => f != null && f.needsReview);

  Map<String, String?> toFields() => {
    'name': name?.value,
    'title': title?.value,
    'company': company?.value,
    'email': emails.firstOrNull?.value,
    'mobile': phones.where((p) => p.label == 'mobile').firstOrNull?.value,
    'office': phones.where((p) => p.label == 'office').firstOrNull?.value,
    'website': website?.value,
    'address': address?.value,
  };
}

final _email = RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}');
final _url = RegExp(
  r'(?:https?://)?(?:www\.)?[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.(?:com|net|org|io|co|us|ca|uk|de|eu|biz|info|ai|app|dev|[a-z]{2})(?:/[^\s]*)?',
  caseSensitive: false,
);
final _phone = RegExp(r'\+?\(?\d[\d\s().\-/]{6,}\d(?:\s*,?\s*(?:x|ext\.?|extension)\s*\d{1,6})?', caseSensitive: false);
final _ext = RegExp(r'\s*,?\s*(?:x|ext\.?|extension)\s*(\d{1,6})$', caseSensitive: false);

/// OCR reads 1 as I/l/| and 0 as O inside numbers ("(440)57I-0609",
/// "Ext. I12"). Fixed only between digit-like characters, so words are safe.
String fixDigitLookalikes(String s) {
  var out = s;
  for (var i = 0; i < 2; i++) {
    out = out.replaceAllMapped(
      RegExp(r'(?<=[\d()\-.\s/])([Il|O])(?=[\d\-.)\s]*\d)|(?<=\d)([Il|O])'),
      (m) => (m[1] ?? m[2]) == 'O' ? '0' : '1',
    );
  }
  // "Ext. I12": the letter right after an extension marker.
  return out.replaceAllMapped(
    RegExp(r'((?:x|ext\.?|extension)\s*)([Il|O])(?=\d)', caseSensitive: false),
    (m) => '${m[1]}${m[2] == 'O' ? '0' : '1'}',
  );
}

final _phoneLabel = RegExp(
  r'\b(mobile|mob|cell|c|m|office|tel|phone|direct|d|o|t|p|fax|f)\b\.?\s*[:.]?\s*$',
  caseSensitive: false,
);

final _postal = [
  RegExp(r'\b[A-Z]{2}\s+\d{5}(?:-\d{4})?\b'), // US: OH 44241
  RegExp(
    r'\b(?:Alabama|Alaska|Arizona|Arkansas|California|Colorado|Connecticut|Delaware|Florida|Georgia|Hawaii|Idaho|Illinois|Indiana|Iowa|Kansas|Kentucky|Louisiana|Maine|Maryland|Massachusetts|Michigan|Minnesota|Mississippi|Missouri|Montana|Nebraska|Nevada|New Hampshire|New Jersey|New Mexico|New York|North Carolina|North Dakota|Ohio|Oklahoma|Oregon|Pennsylvania|Rhode Island|South Carolina|South Dakota|Tennessee|Texas|Utah|Vermont|Virginia|Washington|West Virginia|Wisconsin|Wyoming)\s+\d{5}(?:-\d{4})?\b',
  ), // US: Ohio 44095
  RegExp(r'\b[A-Z]\d[A-Z]\s?\d[A-Z]\d\b'), // CA
  RegExp(r'\b[A-Z]{1,2}\d[A-Z\d]?\s?\d[A-Z]{2}\b'), // UK
  RegExp(r'\b(?:D-|DE-)?\d{5}\s+[A-ZÄÖÜ][a-zäöüß]+'), // DE/EU: 80331 München
];
final _streetHint = RegExp(
  r'\d+\s+\w+|\b(st|street|ave|avenue|rd|road|blvd|dr|drive|suite|ste|way|lane|ln|pkwy|hwy|floor|fl|unit|po box|straße|str\.)\b',
  caseSensitive: false,
);

const _titleWords = [
  'director',
  'vp',
  'vice president',
  'manager',
  'engineer',
  'president',
  'chief',
  'head of',
  'sales',
  'buyer',
  'procurement',
  'ceo',
  'cfo',
  'cto',
  'coo',
  'founder',
  'owner',
  'partner',
  'principal',
  'specialist',
  'coordinator',
  'consultant',
  'analyst',
  'supervisor',
  'lead',
  'officer',
  'representative',
  'account',
  'executive',
  'associate',
  'administrator',
  'designer',
  'developer',
  'architect',
  'technician',
  'purchasing',
  'marketing',
  'operations',
  'superintendent',
  'estimator',
  'agent',
];
final _titleRe = RegExp('\\b(${_titleWords.map(RegExp.escape).join('|')})\\b', caseSensitive: false);

final _legalSuffix = RegExp(
  r'\b(inc|llc|l\.l\.c|ltd|limited|corp|corporation|co|company|gmbh|ag|plc|lp|llp|s\.?a|s\.?r\.?l|pty|group|industries|technologies|solutions)\b\.?',
  caseSensitive: false,
);

const _credentials = {
  'PE',
  'P.E.',
  'MBA',
  'PHD',
  'PH.D.',
  'CPA',
  'PMP',
  'MD',
  'M.D.',
  'ESQ',
  'JR',
  'JR.',
  'SR',
  'SR.',
  'III',
  'II',
  'CSCP',
  'CPIM',
  'SHRM-CP',
  'RN',
  'MS',
  'BS',
};

class _Line {
  final OcrLine src;
  String rest; // text left after contact spans are cut out
  bool used = false;
  _Line(this.src) : rest = src.text.trim();

  /// Field confidence (deep dive §2.6): 0.5 x OCR + 0.3 x rule + 0.2 x cross-check.
  /// Engines without line confidence (and test fixtures) score on the rule alone.
  double score(double rule, {double cross = 0.8}) {
    final ocr = src.confidence;
    return ocr == null ? rule : 0.5 * ocr + 0.3 * rule + 0.2 * cross;
  }
}

/// Parses one card side. [region] is the ISO country for phone parsing,
/// normally the device locale.
ParsedCard parseCard(OcrPage page, {String region = 'US'}) {
  final card = ParsedCard();
  final lines = [
    for (final l in page.lines)
      if (l.text.trim().isNotEmpty) _Line(l),
  ];
  final iso = IsoCode.values.firstWhere((c) => c.name == region.toUpperCase(), orElse: () => IsoCode.US);

  // 0. OCR fix-ups (deep dive §2.7): rejoin emails broken by spaces around
  // "@" or ".", e.g. "sam@brightline. io" or "dana . reyes@acme.com".
  for (final l in lines) {
    if (l.rest.contains('@')) {
      l.rest = l.rest.replaceAllMapped(
        RegExp(r'([A-Za-z0-9_%+\-]+(?:\s*\.\s*[A-Za-z0-9_%+\-]+)*)\s*@\s*([A-Za-z0-9\-]+(?:\s*\.\s*[A-Za-z0-9\-]+)+)'),
        (m) => '${m[1]!.replaceAll(RegExp(r'\s+'), '')}@${m[2]!.replaceAll(RegExp(r'\s+'), '')}',
      );
    }
  }

  // 1. Emails.
  for (final l in lines) {
    for (final m in _email.allMatches(l.rest).toList()) {
      card.emails.add(ParsedField(m[0]!.toLowerCase(), l.score(0.98, cross: 1)));
    }
    l.rest = l.rest.replaceAll(_email, ' ');
  }
  final emailDomains = {for (final e in card.emails) e.value.split('@').last};

  // 1b. Websites.
  final urls = <ParsedField>[];
  for (final l in lines) {
    for (final m in _url.allMatches(l.rest).toList()) {
      final raw = m[0]!;
      if (RegExp(r'^\d').hasMatch(raw)) continue; // "1.5" etc.
      if (!raw.contains('.') || raw.split('.').last.length < 2) continue;
      final bare = raw.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
      final host = bare.split('/').first.toLowerCase().replaceFirst('www.', '');
      final explicit = raw.contains('www.') || raw.contains('://');
      final sure = explicit || emailDomains.contains(host);
      urls.add(ParsedField(bare.toLowerCase(), l.score(sure ? 0.95 : 0.75, cross: sure ? 1 : 0.6)));
      l.rest = l.rest.replaceFirst(raw, ' ');
    }
  }
  // Rule 1: a bare email domain is only kept as the website when nothing better exists.
  final explicitUrls = urls.where((u) => u.value.startsWith('www.') || u.value.contains('/'));
  card.website = explicitUrls.firstOrNull ?? urls.firstOrNull;

  for (final l in lines) {
    if (RegExp(r'\d').hasMatch(l.rest)) l.rest = fixDigitLookalikes(l.rest);
  }

  // 2. Phones, labelled by the token in front of them. Labels are read from the
  // untouched line: "M 330-555-0101  O (330) 555-0199" has two numbers, and
  // cutting the first out before reading the second's label shifts positions.
  for (final l in lines) {
    final text = l.rest;
    final cut = <(int, int)>[]; // spans to blank out afterwards (label + number)
    var prevEnd = 0;
    for (final m in _phone.allMatches(text)) {
      final whole = m[0]!.trim();
      final extMatch = _ext.firstMatch(whole);
      final ext = extMatch?[1] ?? '';
      final raw = extMatch == null ? whole : whole.substring(0, extMatch.start).trim();
      final digits = raw.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 7 || digits.length > 15) continue;
      final before = text.substring(prevEnd, m.start);
      final labelMatch = _phoneLabel.firstMatch(before);
      final lab = labelMatch?[1]?.toLowerCase() ?? '';
      cut.add((labelMatch == null ? m.start : prevEnd + labelMatch.start, m.end));
      prevEnd = m.end;
      String value;
      var rule = 0.9;
      var valid = false;
      try {
        final p = PhoneNumber.parse(raw, callerCountry: iso);
        valid = p.isValid();
        value = valid ? '+${p.countryCode}${p.nsn}' : raw; // E.164, matched exactly on save
        rule = valid ? 0.98 : 0.6;
      } catch (_) {
        value = raw;
        rule = 0.5;
      }
      if (lab.startsWith('f')) {
        card.faxes.add(ParsedPhone(value, l.score(rule, cross: valid ? 1 : 0.5), 'fax', extension: ext));
        continue;
      }
      final label = (lab.startsWith('m') || lab.startsWith('c')) ? 'mobile' : 'office';
      if (lab.isEmpty) rule *= 0.85; // unlabelled: guess office
      card.phones.add(ParsedPhone(value, l.score(rule, cross: valid ? 1 : 0.5), label, extension: ext));
    }
    if (cut.isNotEmpty) {
      final sb = StringBuffer();
      var at = 0;
      for (final (start, end) in cut) {
        sb
          ..write(text.substring(at, start))
          ..write(' ');
        at = end;
      }
      sb.write(text.substring(at));
      l.rest = sb.toString();
    }
  }
  for (final l in lines) {
    l.rest = l.rest.replaceAll(RegExp(r'^[\s|•·,;:/\-]+|[\s|•·,;:/\-]+$'), '').replaceAll(RegExp(r'\s{2,}'), ' ');
    // A label left behind after its value was taken ("E-Mail", "Tel.") is noise.
    final bareLabel = RegExp(
      r'^(e-?mail|email|web(site)?|www|tel|phone|ph|fax|direct|cell|mobile|office|m|t|f|o|p|c)[:.]?$',
      caseSensitive: false,
    );
    if (l.rest.isEmpty || bareLabel.hasMatch(l.rest)) l.used = true;
  }

  // 3. Address: postal-code line plus up to 2 street-looking lines above.
  // The German "80331 München" pattern also fits "34899 Curtis Blvd", so it is
  // only tried when no other format matched any line.
  final strict = _postal.where((r) => r != _postal.last).toList();
  final anyStrict = lines.any((l) => !l.used && strict.any((r) => r.hasMatch(l.rest)));
  for (var i = 0; i < lines.length && card.address == null; i++) {
    final l = lines[i];
    if (l.used || !(anyStrict ? strict : _postal).any((r) => r.hasMatch(l.rest))) continue;
    final parts = [l.rest];
    l.used = true;
    for (var j = i - 1; j >= 0 && j >= i - 2; j--) {
      final up = lines[j];
      if (up.used || !_streetHint.hasMatch(up.rest) || _titleRe.hasMatch(up.rest)) break;
      parts.insert(0, up.rest);
      up.used = true;
    }
    card.address = ParsedField(
      parts.join(', '),
      l.score(parts.length > 1 ? 0.9 : 0.75, cross: parts.length > 1 ? 1 : 0.6),
    );
  }

  // 4. Title: keyword line, whole line kept.
  for (final l in lines) {
    if (l.used || !_titleRe.hasMatch(l.rest)) continue;
    if (_legalSuffix.hasMatch(l.rest)) continue; // "Sales Solutions Inc" is a company
    card.title = ParsedField(titleCaseTitle(l.rest), l.score(0.85));
    l.used = true;
    break;
  }

  // 6a. Company with a legal suffix is unambiguous; take it before the name.
  for (final l in lines) {
    if (l.used || !_legalSuffix.hasMatch(l.rest)) continue;
    card.company = ParsedField(l.rest, l.score(0.9));
    l.used = true;
    break;
  }

  // 6b. Otherwise a line that matches the email/web domain.
  final domainKey = _domainKey(card);
  if (card.company == null && domainKey != null) {
    for (final l in lines) {
      if (l.used) continue;
      if (_norm(l.rest).replaceAll(' ', '').contains(domainKey)) {
        card.company = ParsedField(l.rest, l.score(0.85, cross: 1));
        l.used = true;
        break;
      }
    }
  }

  // 5. Name: tallest unused line of 2–4 capitalised tokens.
  _Line? best;
  String? bestName, bestSuffix;
  for (final l in lines) {
    if (l.used) continue;
    final split = _splitCredentials(l.rest);
    final tokens = split.$1.split(RegExp(r'\s+'));
    if (tokens.length < 2 || tokens.length > 4) continue;
    if (!tokens.every((t) => RegExp(r"^[A-ZÀ-Ý][A-Za-zÀ-ÿ'’.\-]*$").hasMatch(t))) continue;
    if (best == null || l.src.height > best.src.height) {
      best = l;
      bestName = split.$1;
      bestSuffix = split.$2;
    }
  }
  if (best != null) {
    final tallest = lines.map((l) => l.src.height).fold(0.0, (a, b) => a > b ? a : b);
    final isTallest = best.src.height >= tallest * 0.9;
    // A name that also appears in the email local part is near-certain.
    final local = card.emails.firstOrNull?.value.split('@').first ?? '';
    final inEmail = bestName!.toLowerCase().split(' ').any((t) => t.length > 2 && local.contains(t));
    card.name = ParsedField(
      _titleCase(bestName),
      best.score(
        inEmail
            ? 0.95
            : isTallest
            ? 0.85
            : 0.65,
        cross: inEmail ? 1 : (isTallest ? 0.8 : 0.5),
      ),
    );
    if (bestSuffix!.isNotEmpty) card.suffix = ParsedField(bestSuffix, 0.9);
    best.used = true;
  }

  // 6c. Company fallback: derive from the domain, or the tallest leftover line.
  if (card.company == null) {
    final leftovers = lines.where((l) => !l.used).toList()..sort((a, b) => b.src.height.compareTo(a.src.height));
    if (leftovers.isNotEmpty && leftovers.first.src.height > 0 && leftovers.first.rest.length > 2) {
      card.company = ParsedField(leftovers.first.rest, leftovers.first.score(0.6, cross: 0.5));
      leftovers.first.used = true;
    } else if (domainKey != null) {
      card.company = ParsedField(_titleCase(domainKey), 0.5);
    }
  }

  // 7. Everything else: labelled extras when recognisable, else notes.
  for (final l in lines) {
    if (l.used) continue;
    final label = extraLabel(l.rest);
    label == null ? card.notes.add(l.rest) : card.extras.add(ParsedExtra(label, l.rest));
  }
  return card;
}

String? _domainKey(ParsedCard c) {
  final host =
      c.website?.value.split('/').first.replaceFirst('www.', '') ?? c.emails.firstOrNull?.value.split('@').last;
  if (host == null) return null;
  final parts = host.split('.');
  if (parts.length < 2) return null;
  const generic = {'gmail', 'yahoo', 'outlook', 'hotmail', 'icloud', 'aol', 'live', 'proton', 'protonmail'};
  final key = parts[parts.length - 2];
  return generic.contains(key) ? null : key.replaceAll('-', '');
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '');

(String, String) _splitCredentials(String s) {
  final tokens = s.split(RegExp(r'[\s,]+')).where((t) => t.isNotEmpty).toList();
  final suffix = <String>[];
  while (tokens.isNotEmpty && _credentials.contains(tokens.last.toUpperCase())) {
    suffix.insert(0, tokens.removeLast());
  }
  return (tokens.join(' '), suffix.join(', '));
}

final _extraRules = <(String, RegExp)>[
  (
    'Licence',
    RegExp(
      r'\b(lic(ense|ence)?\.?\s*(no\.?|#|number)?|reg\.?\s*(no|#)|cert(ified|ification)?\s*#|dot\s*#|mc\s*#|nmls)\b',
      caseSensitive: false,
    ),
  ),
  (
    'Hours',
    RegExp(
      r'\b(mon|tue|wed|thu|fri|sat|sun)[a-z]*\b.*\d|\b\d{1,2}(:\d{2})?\s*(am|pm)\b|\b24/7\b|open\b',
      caseSensitive: false,
    ),
  ),
  (
    'Social',
    RegExp(
      r'(^|\s)@[A-Za-z0-9_.]{2,}|\b(linkedin|instagram|facebook|twitter|x\.com|youtube|tiktok)\b',
      caseSensitive: false,
    ),
  ),
  ('Since', RegExp(r'\b(est\.?|established|since|founded)\s*(in\s*)?\d{4}\b', caseSensitive: false)),
  ('Tagline', RegExp(r'^[A-Z][^.!?]{8,60}[.!]?$')),
];

/// What a leftover line is, or null to keep it as a plain note.
String? extraLabel(String line) {
  final t = line.trim();
  for (final (label, re) in _extraRules) {
    if (label == 'Tagline') {
      // Slogans: several lower-case words ("Delivering the difference"), not an all-caps word list.
      final words = t.split(RegExp(r'\s+'));
      if (words.length >= 3 && re.hasMatch(t) && t != t.toUpperCase() && !RegExp(r'\d').hasMatch(t)) return label;
      continue;
    }
    if (re.hasMatch(t)) return label;
  }
  return null;
}

/// Re-cases a name read in capitals: "FRED PANETO" -> "Fred Paneto",
/// "MCDONALD" -> "McDonald", "O'BRIEN" -> "O'Brien", "SMITH-JONES" ->
/// "Smith-Jones". Tokens already in mixed case are left alone.
String titleCaseName(String s) => s.split(' ').map(_caseToken).join(' ');

String _caseToken(String t) {
  if (t.isEmpty || t != t.toUpperCase() || !RegExp(r'[A-Z]').hasMatch(t)) return t;
  if (RegExp(r'^[A-Z]\.?$').hasMatch(t)) return t; // initial
  if (RegExp(r'^(II|III|IV)$').hasMatch(t)) return t;
  String word(String w) {
    if (w.isEmpty) return w;
    final lower = w.toLowerCase();
    if (lower.startsWith('mc') && lower.length > 3) return 'Mc${lower[2].toUpperCase()}${lower.substring(3)}';
    return lower[0].toUpperCase() + lower.substring(1);
  }

  return t.split('-').map((h) => h.split(RegExp("(?<=['’])")).map(word).join()).join('-');
}

String _titleCase(String s) => titleCaseName(s);

/// "PLANT MANAGER" -> "Plant Manager"; short acronyms (VP, CEO, IT) and
/// small words stay as expected. Mixed-case titles are left alone.
String titleCaseTitle(String s) {
  if (s != s.toUpperCase() || !RegExp(r'[A-Z]{4}').hasMatch(s)) return s;
  const keep = {
    'VP',
    'SVP',
    'EVP',
    'CEO',
    'CFO',
    'CTO',
    'COO',
    'CIO',
    'CMO',
    'IT',
    'HR',
    'QA',
    'QC',
    'R&D',
    'US',
    'USA',
  };
  const small = {'of', 'and', 'the', 'for', 'in', 'to', '&'};
  final words = s.split(' ');
  return [
    for (final (i, w) in words.indexed)
      keep.contains(w.replaceAll(RegExp(r'[,.]'), ''))
          ? w
          : (i > 0 && small.contains(w.toLowerCase()))
          ? w.toLowerCase()
          : _caseToken(w),
  ].join(' ');
}
