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
// The ending must be a whole word: ".example" is not ".ex" plus "ample" (F13).
final _url = RegExp(
  r'(?:https?://)?(?:www\.)?[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.(?:com|net|org|io|co|us|ca|uk|de|eu|biz|info|ai|app|dev|'
  r'example|company|technology|tech|solutions|services|systems|agency|studio|design|digital|media|online|site|store|shop|'
  r'group|global|world|pro|health|law|legal|consulting|engineering|industries|supply|tools|works|email|xyz|me|tv|'
  r'games|game|dental|clinic|care|doctor|auto|cars|coffee|cafe|restaurant|pizza|bar|art|gallery|photography|photo|'
  r'travel|fitness|realty|homes|house|insurance|finance|money|academy|school|education|church|team|club|life|live|'
  r'fun|plus|network|cloud|software|build|construction|repair|farm|garden|pet|pets|vet|beauty|salon|fashion|shoes|'
  r'jewelry|wine|beer|events|wedding|center|city|nyc|land|space|today|news|blog|page|link|one|zone|'
  r'[a-z]{2})(?![A-Za-z0-9\-])(?:/[^\s]*)?',
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

final _phoneLabelAfter = RegExp(
  r'^\s*[(\[]?\s*(mobile|cell|office|direct|fax|tel|phone|main|work)\b[)\]]?\.?',
  caseSensitive: false,
);
final _phoneLabel = RegExp(
  r'\b(mobile|mob|cell|c|m|office|tel|phone|direct|d|o|t|p|fax|f|sales|main|work|support|reception)\b\.?\s*[:.]?\s*$',
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
  r'\b(inc|llc|l\.l\.c|ltd|limited|corp|corporation|co|company|gmbh|ag|plc|lp|llp|s\.?a|s\.?r\.?l|pty|group|industries|technologies|solutions|'
  r'supply|supplies|manufacturing|mfg|enterprises|holdings)\b\.?',
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
  'DDS',
  'D.D.S.',
  'DMD',
  'D.M.D.',
  'DVM',
  'OD',
  'PHARMD',
  'JD',
  'ESQ.',
  'CFA',
  'CFP',
  'LCSW',
  'NP',
  'PA-C',
  'DC',
  'AIA',
  'IV',
};

/// Honorifics in front of a name; kept with the credentials, never as a first name.
const _prefixes = {'DR', 'DR.', 'MR', 'MR.', 'MRS', 'MRS.', 'MS', 'MS.', 'MX', 'MX.', 'PROF', 'PROF.', 'REV', 'REV.'};

class _Line {
  final OcrLine src;
  String rest; // text left after contact spans are cut out
  bool used = false;
  // Capped: a real card line is short, and the field regexes slow down badly on
  // very long input (audit MOB-SEC-0101).
  _Line(this.src) : rest = _cap(src.text.trim());

  static String _cap(String s) => s.length > maxLineLength ? s.substring(0, maxLineLength) : s;

  /// Field confidence (deep dive §2.6): 0.5 x OCR + 0.3 x rule + 0.2 x cross-check.
  /// Engines without line confidence (and test fixtures) score on the rule alone.
  double score(double rule, {double cross = 0.8}) {
    final ocr = src.confidence;
    return ocr == null ? rule : 0.5 * ocr + 0.3 * rule + 0.2 * cross;
  }
}

/// Longest OCR line read, and most lines per side (audit MOB-SEC-0101).
const maxLineLength = 200;
const maxLines = 80;

/// Parses one card side. [region] is the ISO country for phone parsing,
/// normally the device locale.
ParsedCard parseCard(OcrPage page, {String region = 'US'}) {
  final card = ParsedCard();
  final lines = [
    for (final l in page.lines.take(maxLines))
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

  // Small-caps print reads as "cOMPRESSORS" / "BLOWERs": one stray lower-case
  // letter at either end of a capitals word is a misread capital (F12).
  for (final l in lines) {
    l.rest = l.rest.replaceAllMapped(RegExp(r'\b(?:[a-z][A-Z]{3,}|[A-Z]{3,}[a-z])\b'), (m) => m[0]!.toUpperCase());
  }

  // A phone label printed in its own column ("M" left of "+1 234 280 5072")
  // is read as a separate line: give it to the number on the same row (F8).
  final labelOnly = RegExp(r'^(mobile|mob|cell|c|m|office|tel|phone|direct|d|o|t|p|fax|f)[:.]?$', caseSensitive: false);
  for (final l in lines) {
    if (!labelOnly.hasMatch(l.rest) || l.src.height <= 0) continue;
    final mid = l.src.top + l.src.height / 2;
    for (final p in lines) {
      if (identical(p, l) || !_phone.hasMatch(p.rest) || _phoneLabel.hasMatch(p.rest.split(_phone).first)) continue;
      final pm = p.src.top + p.src.height / 2;
      if ((pm - mid).abs() > p.src.height * 0.6 || p.src.left < l.src.left) continue;
      p.rest = '${l.rest} ${p.rest}';
      l.rest = '';
      break;
    }
  }

  // 1. Emails.
  for (final l in lines) {
    for (final m in _email.allMatches(l.rest).toList()) {
      card.emails.add(ParsedField(m[0]!.toLowerCase(), l.score(0.98, cross: 1)));
    }
    l.rest = l.rest.replaceAll(_email, ' ');
  }
  // An email the reader garbled ("marisol@ironbridge,example", no dot) is kept
  // and flagged for checking rather than dropped (F19).
  for (final l in lines) {
    final m = RegExp(r'([A-Za-z0-9._%+\-]+)\s*@\s*([A-Za-z0-9\-]+)(?:[\s,;:]+([A-Za-z]{2,}))?').firstMatch(l.rest);
    if (m == null) continue;
    final value = '${m[1]}@${m[2]}${m[3] == null ? '' : '.${m[3]}'}'.toLowerCase();
    card.emails.add(ParsedField(value, 0.5));
    l.rest = l.rest.replaceFirst(m[0]!, ' ');
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
      var lab = labelMatch?[1]?.toLowerCase() ?? '';
      var end = m.end;
      // A label printed after the number ("216.432.5822 office", "… cell"):
      // whole words only, so the next number's "O" or "M" isn't taken.
      if (lab.isEmpty) {
        final after = _phoneLabelAfter.firstMatch(text.substring(m.end));
        // "330-555-0190 Fax 330-555-0191": that word labels the next number.
        final labelsNext = after != null && RegExp(r'^\s*[:.]?\s*[(+]?\d').hasMatch(text.substring(m.end + after.end));
        if (after != null && !labelsNext) {
          lab = after[1]!.toLowerCase();
          end = m.end + after.end;
        }
      }
      cut.add((labelMatch == null ? m.start : prevEnd + labelMatch.start, end));
      prevEnd = end;
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
      final label = const {'mobile', 'mob', 'cell', 'c', 'm'}.contains(lab) ? 'mobile' : 'office';
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
    // A label left behind after its value was taken ("E-Mail", "Tel.", "E:") is
    // noise, never a note (F21).
    final bareLabel = RegExp(
      r'^(e-?mail|email|mail|web(site)?|www|url|tel|phone|ph|fax|direct|cell|mobile|office|sales|main|[a-z])[:.]?$',
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
      // "Dr. Philip J Znidarsic" is a person, not "Dr" for Drive.
      if (_prefixes.contains(up.rest.split(RegExp(r'\s+')).first.toUpperCase())) break;
      parts.insert(0, up.rest);
      up.used = true;
    }
    // "Visit us: 2200 Industrial Pkwy": the lead-in is not part of the address.
    parts[0] = parts[0].replaceFirst(
      RegExp(r'^(visit us|find us|located at|location|address|visit)\s*:?\s*', caseSensitive: false),
      '',
    );
    card.address = ParsedField(
      parts.join(', '),
      l.score(parts.length > 1 ? 0.9 : 0.75, cross: parts.length > 1 ? 1 : 0.6),
    );
  }

  // 3b. A country on its own line belongs to the address, not the notes (F9).
  final country = RegExp(
    r'^(usa|u\.s\.a\.?|us|united states( of america)?|canada|mexico|united kingdom|uk|england|germany|deutschland|ireland|australia)$',
    caseSensitive: false,
  );
  if (card.address != null) {
    for (final l in lines) {
      if (l.used || !country.hasMatch(l.rest)) continue;
      card.address = ParsedField('${card.address!.value}, ${l.rest}', card.address!.confidence);
      l.used = true;
      break;
    }
  }

  // 4. Title: keyword line, whole line kept. A "NAME, TITLE" line gives both:
  // the title now, the name part is left for step 5.
  for (final l in lines) {
    if (l.used) continue;
    final both = splitNameTitle(l.rest);
    if (both == null) continue;
    card.title = ParsedField(titleCaseTitle(both.$2), l.score(0.85));
    l.rest = both.$1;
    break;
  }
  // ...and a name and title run together with no mark between them.
  final local = card.emails.firstOrNull?.value.split('@').first ?? '';
  for (final l in lines) {
    if (card.title != null) break;
    if (l.used) continue;
    final run = splitNameTitleRun(l.rest, local);
    if (run == null) continue;
    card.title = ParsedField(titleCaseTitle(run.$2), l.score(0.8));
    l.rest = run.$1;
    break;
  }
  for (final l in lines) {
    if (card.title != null) break;
    if (l.used || !_titleRe.hasMatch(l.rest) || _isSlogan(l.rest)) continue;
    if (_legalSuffix.hasMatch(l.rest)) continue; // "Sales Solutions Inc" is a company
    card.title = ParsedField(titleCaseTitle(l.rest), l.score(0.85));
    l.used = true;
    break;
  }

  // 6a. Company with a legal suffix is unambiguous; take it before the name.
  _Line? companyLine;
  for (final l in lines) {
    if (l.used || !_legalSuffix.hasMatch(l.rest) || _isSlogan(l.rest)) continue;
    card.company = ParsedField(titleCaseCompany(l.rest), l.score(0.9));
    l.used = true;
    companyLine = l;
    break;
  }

  // 6b. Otherwise a line that matches the email/web domain.
  final domainKey = _domainKey(card);
  if (card.company == null && domainKey != null) {
    for (final l in lines) {
      if (l.used) continue;
      if (_norm(l.rest).replaceAll(' ', '').contains(domainKey)) {
        card.company = ParsedField(titleCaseCompany(l.rest), l.score(0.85, cross: 1));
        l.used = true;
        companyLine = l;
        break;
      }
    }
  }

  // 6b2. A company printed over two lines, a big logo word above the rest
  // ("NORDONIA" over "Dental Group"), is one name (real-card test).
  void joinCompanyLines(_Line companyLine) {
    final i = lines.indexOf(companyLine);
    final up = i > 0 ? lines[i - 1] : null;
    if (up != null && !up.used && joinsCompany(up.rest, up.src.height, companyLine.src.height, domainKey)) {
      card.company = ParsedField('${titleCaseCompany(up.rest)} ${card.company!.value}', card.company!.confidence);
      up.used = true;
    }
    // ...or the rest under it: "BRIGHTWATER" over "Family Dental" (0.7.0 phone test).
    final down = i + 1 < lines.length ? lines[i + 1] : null;
    if (down != null && !down.used && continuesCompany(down.rest, down.src.height, companyLine.src.height)) {
      card.company = ParsedField('${card.company!.value} ${titleCaseCompany(down.rest)}', card.company!.confidence);
      down.used = true;
    }
  }

  if (companyLine != null) joinCompanyLines(companyLine);

  // 5. Name: tallest unused line of 2–4 capitalised tokens. A line found in the
  // email's local part wins over a taller one; headings and slogans ("An Emcor
  // Company", "Corporate Office", "Delivering The Difference") never qualify (F18).
  bool inLocal(String name) => name.toLowerCase().split(' ').any((t) => t.length > 2 && local.contains(t));
  _Line? best;
  String? bestName, bestSuffix;
  var bestInEmail = false;
  var bestHasCredential = false;
  for (final l in lines) {
    if (l.used) continue;
    final split = _splitCredentials(l.rest);
    // "PatrickJ. Walsh": the reader dropped the space before an initial (F10).
    final candidate = split.$1.replaceAllMapped(RegExp(r'(?<=[a-z])([A-Z]\.)(?=\s|$)'), (m) => ' ${m[1]}');
    final tokens = candidate.split(RegExp(r'\s+'));
    if (tokens.length < 2 || tokens.length > 4) continue;
    if (!tokens.every((t) => RegExp(r"^[A-ZÀ-Ý][A-Za-zÀ-ÿ'’.\-]*$").hasMatch(t))) continue;
    if (tokens.any((t) => _notNameWords.contains(t.toLowerCase().replaceAll(RegExp(r'[.,]'), '')))) continue;
    // "Family Dental", "Dental Group": business words, not a person (0.7.0 phone test).
    if (tokens.any((t) => _businessWords.contains(t.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '')))) continue;
    final inEmail = inLocal(candidate);
    // "Dr. ..." or "... DDS" is a person's name, whatever is printed bigger.
    final hasCredential = split.$2.isNotEmpty;
    final better =
        best == null ||
        (hasCredential && !bestHasCredential) ||
        (hasCredential == bestHasCredential &&
            ((inEmail && !bestInEmail) || (inEmail == bestInEmail && l.src.height > best.src.height)));
    if (better) {
      best = l;
      bestName = candidate;
      bestSuffix = split.$2;
      bestInEmail = inEmail;
      bestHasCredential = hasCredential;
    }
  }
  if (best != null) {
    final tallest = lines.map((l) => l.src.height).fold(0.0, (a, b) => a > b ? a : b);
    final isTallest = best.src.height >= tallest * 0.9;
    // A name that also appears in the email local part is near-certain.
    final inEmail = bestInEmail;
    card.name = ParsedField(
      _titleCase(bestName!),
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
  } else {
    // A name the reader printed in odd case ("Steve soto") that the email backs up.
    final localLower = local.toLowerCase();
    for (final l in lines) {
      if (l.used || localLower.isEmpty) continue;
      final words = l.rest.trim().split(RegExp(r'\s+'));
      if (words.length < 2 || words.length > 3 || !words.every((w) => RegExp(r"^[A-Za-zÀ-ÿ'’.\-]+$").hasMatch(w))) {
        continue;
      }
      if (_titleRe.hasMatch(l.rest) || _legalSuffix.hasMatch(l.rest) || _isSlogan(l.rest)) continue;
      if (words.any((w) => _notNameWords.contains(w.toLowerCase()) || _businessWords.contains(w.toLowerCase()))) {
        continue;
      }
      if (domainKey != null && _norm(l.rest).replaceAll(' ', '').contains(domainKey)) continue;
      if (!words.any((w) => w.length > 2 && localLower.contains(w.toLowerCase().replaceAll('.', '')))) continue;
      final cased = words.map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
      card.name = ParsedField(_titleCase(cased), l.score(0.55, cross: 0.5));
      l.used = true;
      break;
    }
    // No printed name found: "travis.dingee@" still gives one, to be checked.
    final m = RegExp(r'^([a-z]{2,})[._\-]([a-z]{2,})$').firstMatch(local);
    if (card.name == null && m != null) {
      card.name = ParsedField(_titleCase('${m[1]!.toUpperCase()} ${m[2]!.toUpperCase()}'), 0.5);
    }
  }

  // 6c. Company fallback: derive from the domain, or the tallest leftover line.
  if (card.company == null) {
    final leftovers =
        lines
            .where(
              (l) =>
                  !l.used &&
                  !_isSlogan(l.rest) &&
                  !RegExp(r'www\.|https?://', caseSensitive: false).hasMatch(l.rest) &&
                  // Opening hours, a licence or a handle is never the company.
                  !const {'Hours', 'Licence', 'Social', 'Since'}.contains(extraLabel(l.rest)),
            )
            .toList()
          ..sort((a, b) => b.src.height.compareTo(a.src.height));
    if (leftovers.isNotEmpty && leftovers.first.src.height > 0 && leftovers.first.rest.length > 2) {
      card.company = ParsedField(titleCaseCompany(leftovers.first.rest), leftovers.first.score(0.6, cross: 0.5));
      leftovers.first.used = true;
      joinCompanyLines(leftovers.first);
    } else if (domainKey != null) {
      card.company = ParsedField(domainKey[0].toUpperCase() + domainKey.substring(1), 0.5);
    }
  }

  // 6d. The domain is printed by the business itself, so its spelling wins: a logo
  // swirl read as a letter glued to the name ("Oenpress LLC" with enpress.com) loses
  // the stray letter (phone test F38).
  if (card.company != null && domainKey != null) {
    final fixed = alignCompanyToDomain(card.company!.value, domainKey);
    if (fixed != card.company!.value) card.company = ParsedField(fixed, card.company!.confidence);
  }
  if (card.company != null) {
    final fixed = normaliseLlc(card.company!.value);
    // Re-cased once fixed: "ENPRESS LuC" was mixed case, so it was left as read.
    if (fixed != card.company!.value) card.company = ParsedField(titleCaseCompany(fixed), card.company!.confidence);
  }

  // 7. Everything else: labelled extras when recognisable, else notes.
  for (final l in lines) {
    if (l.used) continue;
    final label = extraLabel(l.rest);
    var text = l.rest;
    if (label == 'Tagline' && text == text.toUpperCase()) text = titleCaseCompany(text);
    // "Mon-Fri7:30-6:00": the reader dropped the space after the days.
    if (label == 'Hours') text = text.replaceAllMapped(RegExp(r'([A-Za-z])(\d)'), (m) => '${m[1]} ${m[2]}');
    label == null ? card.notes.add(text) : card.extras.add(ParsedExtra(label, text));
  }
  return card;
}

/// Words that make a line a heading or slogan, never a person's name.
const _notNameWords = {
  'a', 'an', 'the', 'of', 'and', 'for', 'at', 'to', 'your', 'our', 'we', //
  'company', 'corporate', 'office', 'offices', 'headquarters', 'division', 'department', 'branch',
  'delivering', 'difference', 'solutions', 'innovation', 'quality', 'service', 'services', 'excellence',
  'welcome', 'since', 'trusted', 'leader', 'leaders', 'leading', 'partner', 'partners', 'together',
};

String? _domainKey(ParsedCard c) {
  final host =
      c.website?.value
          .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
          .split('/')
          .first
          .replaceFirst('www.', '') ??
      c.emails.firstOrNull?.value.split('@').last;
  if (host == null) return null;
  final parts = host.split('.');
  if (parts.length < 2) return null;
  const generic = {'gmail', 'yahoo', 'outlook', 'hotmail', 'icloud', 'aol', 'live', 'proton', 'protonmail'};
  final key = parts[parts.length - 2];
  return generic.contains(key) ? null : key.replaceAll('-', '');
}

/// Drops one stray leading character from the company's first word when the rest
/// is exactly the email/web domain name ("Oenpress" + enpress.com -> "Enpress").
String alignCompanyToDomain(String company, String domainKey) {
  final words = company.split(' ');
  final first = words.first;
  final letters = first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (letters.length != domainKey.length + 1 || letters.substring(1) != domainKey) return company;
  final rest = first.substring(1);
  if (rest.isEmpty) return company;
  final wasUpper = first == first.toUpperCase();
  words[0] = wasUpper ? rest.toUpperCase() : rest[0].toUpperCase() + rest.substring(1).toLowerCase();
  return words.join(' ');
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '');

/// "Dr. Philip J Znidarsic DDS" -> ("Philip J Znidarsic", "Dr., DDS"): honorifics
/// in front and credentials behind are kept together, apart from the name.
(String, String) _splitCredentials(String s) {
  final tokens = s.split(RegExp(r'[\s,]+')).where((t) => t.isNotEmpty).toList();
  final kept = <String>[];
  if (tokens.length > 2 && _prefixes.contains(tokens.first.toUpperCase())) kept.add(tokens.removeAt(0));
  final suffix = <String>[];
  while (tokens.isNotEmpty && _credentials.contains(tokens.last.toUpperCase())) {
    suffix.insert(0, tokens.removeLast());
  }
  return (tokens.join(' '), [...kept, ...suffix].join(', '));
}

/// "BRIAN BERG, DIRECTOR OF OPERATIONS": a name and a title printed on one line
/// are split at the comma (real-card test). Returns null when it is not that.
///
/// A slash, bar, dash or bullet splits the same way ("Steve Soto / Manager of QSE").
/// It is a name and a title only when the first part reads as a name and the
/// second holds a title word, so "Sales / Service" and street lines are left alone.
(String, String)? splitNameTitle(String s) {
  final sep = RegExp(r'\s*(?:,|/|\||[–—•·]|\s-\s)\s*').firstMatch(s);
  if (sep == null) return null;
  final name = s.substring(0, sep.start).trim();
  final title = s.substring(sep.end).trim();
  if (title.isEmpty || !_titleRe.hasMatch(title) || _legalSuffix.hasMatch(name)) return null;
  final tokens = _splitCredentials(name).$1.split(RegExp(r'\s+'));
  if (tokens.length < 2 || tokens.length > 4) return null;
  if (!tokens.every((t) => RegExp(r"^[A-ZÀ-Ý][A-Za-zÀ-ÿ'’.\-]*$").hasMatch(t))) return null;
  if (tokens.any((t) => _notNameWords.contains(t.toLowerCase()))) return null;
  return (name, title);
}

/// "Steve Soto Manager of QSE": the reader ran a name and a title together with
/// no mark between. Split only when the first words are name-shaped, none of them
/// is a title or business word, and one of them is in the email's local part
/// ("steve.soto@..."), which is what makes it a person rather than a job title.
(String, String)? splitNameTitleRun(String s, String emailLocal) {
  if (emailLocal.isEmpty) return null;
  final tokens = s.trim().split(RegExp(r'\s+'));
  final local = emailLocal.toLowerCase();
  for (var k = 2; k <= 3 && k < tokens.length; k++) {
    final name = tokens.sublist(0, k);
    final title = tokens.sublist(k).join(' ');
    if (!_titleRe.hasMatch(tokens[k]) || !_titleRe.hasMatch(title)) continue;
    if (!name.every((t) => RegExp(r"^[A-ZÀ-Ý][A-Za-zÀ-ÿ'’.\-]*$").hasMatch(t))) continue;
    if (name.any((t) => _titleRe.hasMatch(t) || _notNameWords.contains(t.toLowerCase()))) continue;
    if (name.any((t) => _businessWords.contains(t.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '')))) continue;
    if (!name.any((t) => t.length > 2 && local.contains(t.toLowerCase().replaceAll('.', '')))) continue;
    return (name.join(' '), title);
  }
  return null;
}

/// A logo word over the company line belongs to it: one or two words, no digits,
/// about as big, and either all capitals or part of the email/web domain.
bool joinsCompany(String above, double aboveHeight, double companyHeight, String? domainKey) {
  final words = above.trim().split(RegExp(r'\s+'));
  if (words.isEmpty || words.length > 2 || RegExp(r'[\d@]').hasMatch(above)) return false;
  if (_titleRe.hasMatch(above) || _legalSuffix.hasMatch(above) || _isSlogan(above)) return false;
  if (companyHeight > 0 && aboveHeight < companyHeight * 0.8) return false;
  final key = _norm(above).replaceAll(' ', '');
  final inDomain = domainKey != null && key.length > 2 && domainKey.contains(key);
  return inDomain || above == above.toUpperCase();
}

/// The second half of a company printed under its logo word: one to three words,
/// no digits, at least one a business word ("Family Dental", "Dental Group").
bool continuesCompany(String below, double belowHeight, double companyHeight) {
  final words = below.trim().split(RegExp(r'\s+'));
  if (words.isEmpty || words.length > 3 || RegExp(r'[\d@]').hasMatch(below)) return false;
  if (_titleRe.hasMatch(below) || _isSlogan(below)) return false;
  if (companyHeight > 0 && belowHeight < companyHeight * 0.5) return false;
  return words.any((w) => _businessWords.contains(w.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '')));
}

const _businessWords = {
  'dental', 'dentistry', 'orthodontics', 'clinic', 'medical', 'health', 'healthcare', 'care', 'group', //
  'studio', 'studios', 'law', 'legal', 'insurance', 'realty', 'associates', 'partners', 'center', 'centre',
  'labs', 'lab', 'works', 'supply', 'services', 'solutions', 'systems', 'industries', 'games', 'design',
};

/// A slogan or call to action ("SEE OUR FULL HOARD OF ... AT:", "FREE
/// DOWNLOADS!"): never a company, a name or a title.
bool _isSlogan(String s) {
  final words = s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.length > 5) return true;
  if (RegExp(r'[:!?]$').hasMatch(s.trim())) return true;
  return words.any((w) => _sloganWords.contains(w.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '')));
}

const _sloganWords = {
  'our',
  'your',
  'see',
  'visit',
  'get',
  'free',
  'makers',
  'call',
  'order',
  'more',
  'we',
  // "Proudly Serving the Aerospace Industry" (sweep test, a card whose logo says LUNAR).
  'proudly',
  'serving',
  'industry',
};

/// The last word of a company read as "LuC", "LIC", "L1C", "L.L.C" or "LLG"
/// (OCR of LLC, sweep test "ENPRESS LuC") becomes "LLC".
String normaliseLlc(String company) {
  final words = company.trim().split(RegExp(r'\s+'));
  if (words.length < 2) return company;
  final last = words.last;
  if (!RegExp(r'^L\.?[LIlu1|]\.?[CGc]\.?$').hasMatch(last)) return company;
  return [...words.take(words.length - 1), 'LLC'].join(' ');
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
      // A capitals list split by dashes is a shop's tagline ("BRAKES - TIRES - OIL CHANGE").
      if (RegExp(r'^[A-Z][A-Z &]+( - [A-Z][A-Z &]+){2,}$').hasMatch(t)) return label;
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

/// "NORTHWIND FORGING INC." -> "Northwind Forging Inc." (F11). Legal forms and
/// acronyms keep their capitals (LLC, USA, H&S); mixed-case names are left alone.
String titleCaseCompany(String s) {
  if (s != s.toUpperCase() || !RegExp(r'[A-Z]{4}').hasMatch(s)) return s;
  const keep = {'LLC', 'LLP', 'LP', 'PLC', 'AG', 'SA', 'NV', 'BV', 'AB', 'USA', 'US', 'UK', 'EU', 'IT', 'HR', 'QA'};
  const proper = {'INC': 'Inc', 'CORP': 'Corp', 'CO': 'Co', 'LTD': 'Ltd', 'GMBH': 'GmbH', 'MFG': 'Mfg'};
  const small = {'of', 'and', 'the', 'for', 'in', 'at', '&'};
  final words = s.split(' ');
  return [
    for (final (i, w) in words.indexed)
      () {
        final core = w.replaceAll(RegExp(r'[,.]'), '');
        if (keep.contains(core) || w.contains('&') || RegExp(r'^([A-Z]\.){2,}$').hasMatch(w)) return w;
        if (proper.containsKey(core)) return w.replaceFirst(core, proper[core]!);
        if (i > 0 && small.contains(w.toLowerCase())) return w.toLowerCase();
        return _caseToken(w);
      }(),
  ].join(' ');
}
