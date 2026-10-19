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
  /// mobile | office (fax never appears here, it goes to notes).
  final String label;
  const ParsedPhone(super.value, super.confidence, this.label);
}

class ParsedCard {
  ParsedField? name, suffix, title, company, address, website;
  final emails = <ParsedField>[];
  final phones = <ParsedPhone>[];
  final notes = <String>[];

  bool get needsReview => [name, title, company, address, website, ...emails, ...phones]
      .any((f) => f != null && f.needsReview);

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
    caseSensitive: false);
final _phone = RegExp(r'\+?\(?\d[\d\s().\-/]{6,}\d(?:\s*(?:x|ext\.?)\s*\d{1,5})?');
final _phoneLabel = RegExp(
    r'\b(mobile|mob|cell|c|m|office|tel|phone|direct|d|o|t|p|fax|f)\b\.?\s*[:.]?\s*$',
    caseSensitive: false);

final _postal = [
  RegExp(r'\b[A-Z]{2}\s+\d{5}(?:-\d{4})?\b'), // US: OH 44241
  RegExp(r'\b[A-Z]\d[A-Z]\s?\d[A-Z]\d\b'), // CA
  RegExp(r'\b[A-Z]{1,2}\d[A-Z\d]?\s?\d[A-Z]{2}\b'), // UK
  RegExp(r'\b(?:D-|DE-)?\d{5}\s+[A-ZÄÖÜ][a-zäöüß]+'), // DE/EU: 80331 München
];
final _streetHint = RegExp(
    r'\d+\s+\w+|\b(st|street|ave|avenue|rd|road|blvd|dr|drive|suite|ste|way|lane|ln|pkwy|hwy|floor|fl|unit|po box|straße|str\.)\b',
    caseSensitive: false);

const _titleWords = [
  'director', 'vp', 'vice president', 'manager', 'engineer', 'president',
  'chief', 'head of', 'sales', 'buyer', 'procurement', 'ceo', 'cfo', 'cto',
  'coo', 'founder', 'owner', 'partner', 'principal', 'specialist',
  'coordinator', 'consultant', 'analyst', 'supervisor', 'lead', 'officer',
  'representative', 'account', 'executive', 'associate', 'administrator',
  'designer', 'developer', 'architect', 'technician', 'purchasing',
  'marketing', 'operations', 'superintendent', 'estimator', 'agent',
];
final _titleRe = RegExp(
    '\\b(${_titleWords.map(RegExp.escape).join('|')})\\b', caseSensitive: false);

final _legalSuffix = RegExp(
    r'\b(inc|llc|l\.l\.c|ltd|limited|corp|corporation|co|company|gmbh|ag|plc|lp|llp|s\.?a|s\.?r\.?l|pty|group|industries|technologies|solutions)\b\.?',
    caseSensitive: false);

const _credentials = {
  'PE', 'P.E.', 'MBA', 'PHD', 'PH.D.', 'CPA', 'PMP', 'MD', 'M.D.', 'ESQ',
  'JR', 'JR.', 'SR', 'SR.', 'III', 'II', 'CSCP', 'CPIM', 'SHRM-CP', 'RN', 'MS', 'BS',
};

class _Line {
  final OcrLine src;
  String rest; // text left after contact spans are cut out
  bool used = false;
  _Line(this.src) : rest = src.text.trim();
  double get conf => src.confidence ?? 1.0;
}

/// Parses one card side. [region] is the ISO country for phone parsing,
/// normally the device locale.
ParsedCard parseCard(OcrPage page, {String region = 'US'}) {
  final card = ParsedCard();
  final lines = [for (final l in page.lines) if (l.text.trim().isNotEmpty) _Line(l)];
  final iso = IsoCode.values.firstWhere((c) => c.name == region.toUpperCase(),
      orElse: () => IsoCode.US);

  // 1. Emails.
  for (final l in lines) {
    for (final m in _email.allMatches(l.rest).toList()) {
      card.emails.add(ParsedField(m[0]!.toLowerCase(), 0.98 * l.conf));
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
      urls.add(ParsedField(bare.toLowerCase(),
          (explicit || emailDomains.contains(host) ? 0.95 : 0.75) * l.conf));
      l.rest = l.rest.replaceFirst(raw, ' ');
    }
  }
  // Rule 1: a bare email domain is only kept as the website when nothing better exists.
  final explicitUrls = urls.where((u) => u.value.startsWith('www.') || u.value.contains('/'));
  card.website = explicitUrls.firstOrNull ?? urls.firstOrNull;

  // 2. Phones, labelled by the token in front of them.
  for (final l in lines) {
    for (final m in _phone.allMatches(l.rest).toList()) {
      final raw = m[0]!.trim();
      final digits = raw.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 7 || digits.length > 15) continue;
      final before = l.rest.substring(0, m.start);
      final lab = _phoneLabel.firstMatch(before)?[1]?.toLowerCase() ?? '';
      l.rest = l.rest.replaceFirst(raw, ' ');
      if (lab.isNotEmpty) l.rest = l.rest.replaceFirst(_phoneLabel, ' ');
      String value;
      var conf = 0.9;
      try {
        final p = PhoneNumber.parse(raw, callerCountry: iso);
        if (p.isValid()) {
          value = '+${p.countryCode}${p.nsn}'; // E.164, matched exactly on save
          conf = 0.98;
        } else {
          value = raw;
          conf = 0.6;
        }
      } catch (_) {
        value = raw;
        conf = 0.5;
      }
      if (lab.startsWith('f')) {
        card.notes.add('Fax: $value');
        continue;
      }
      final label = (lab.startsWith('m') || lab.startsWith('c')) ? 'mobile' : 'office';
      if (lab.isEmpty) conf *= 0.85; // unlabelled: guess office
      card.phones.add(ParsedPhone(value, conf * l.conf, label));
    }
  }
  for (final l in lines) {
    l.rest = l.rest.replaceAll(RegExp(r'^[\s|•·,;:/\-]+|[\s|•·,;:/\-]+$'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ');
    if (l.rest.isEmpty) l.used = true;
  }

  // 3. Address: postal-code line plus up to 2 street-looking lines above.
  for (var i = 0; i < lines.length && card.address == null; i++) {
    final l = lines[i];
    if (l.used || !_postal.any((r) => r.hasMatch(l.rest))) continue;
    final parts = [l.rest];
    l.used = true;
    for (var j = i - 1; j >= 0 && j >= i - 2; j--) {
      final up = lines[j];
      if (up.used || !_streetHint.hasMatch(up.rest) || _titleRe.hasMatch(up.rest)) break;
      parts.insert(0, up.rest);
      up.used = true;
    }
    card.address = ParsedField(parts.join(', '), (parts.length > 1 ? 0.9 : 0.75) * l.conf);
  }

  // 4. Title: keyword line, whole line kept.
  for (final l in lines) {
    if (l.used || !_titleRe.hasMatch(l.rest)) continue;
    if (_legalSuffix.hasMatch(l.rest)) continue; // "Sales Solutions Inc" is a company
    card.title = ParsedField(l.rest, 0.85 * l.conf);
    l.used = true;
    break;
  }

  // 6a. Company with a legal suffix is unambiguous; take it before the name.
  for (final l in lines) {
    if (l.used || !_legalSuffix.hasMatch(l.rest)) continue;
    card.company = ParsedField(l.rest, 0.9 * l.conf);
    l.used = true;
    break;
  }

  // 6b. Otherwise a line that matches the email/web domain.
  final domainKey = _domainKey(card);
  if (card.company == null && domainKey != null) {
    for (final l in lines) {
      if (l.used) continue;
      if (_norm(l.rest).replaceAll(' ', '').contains(domainKey)) {
        card.company = ParsedField(l.rest, 0.85 * l.conf);
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
    card.name = ParsedField(_titleCase(bestName), (inEmail ? 0.95 : isTallest ? 0.85 : 0.65) * best.conf);
    if (bestSuffix!.isNotEmpty) card.suffix = ParsedField(bestSuffix, 0.9);
    best.used = true;
  }

  // 6c. Company fallback: derive from the domain, or the tallest leftover line.
  if (card.company == null) {
    final leftovers = lines.where((l) => !l.used).toList()
      ..sort((a, b) => b.src.height.compareTo(a.src.height));
    if (leftovers.isNotEmpty && leftovers.first.src.height > 0 &&
        leftovers.first.rest.length > 2) {
      card.company = ParsedField(leftovers.first.rest, 0.6 * leftovers.first.conf);
      leftovers.first.used = true;
    } else if (domainKey != null) {
      card.company = ParsedField(_titleCase(domainKey), 0.5);
    }
  }

  // 7. Everything else is notes.
  for (final l in lines) {
    if (!l.used) card.notes.add(l.rest);
  }
  return card;
}

String? _domainKey(ParsedCard c) {
  final host = c.website?.value.split('/').first.replaceFirst('www.', '') ??
      c.emails.firstOrNull?.value.split('@').last;
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

/// "DANA REYES" -> "Dana Reyes"; mixed case like "McAllister" is left alone.
String _titleCase(String s) => s.split(' ').map((t) {
      if (t.isEmpty || t != t.toUpperCase()) return t;
      return t[0] + t.substring(1).toLowerCase();
    }).join(' ');
