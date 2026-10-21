/// Duplicate matching (roadmap S8.1, S8.2). Pure Dart so the table tests run
/// without a database.
library;

import 'dart:math' as math;

import '../text/normalize.dart';

/// What the matcher knows about one person.
class MatchCandidate {
  final String id;
  final String name; // display name as printed
  final String company; // current company as printed, '' when none
  final Set<String> mobiles; // E.164 where valid
  final Set<String> emails; // lower case

  MatchCandidate({required this.id, required this.name, this.company = '', Set<String>? mobiles, Set<String>? emails})
    : mobiles = mobiles ?? const {},
      emails = emails ?? const {};

  late final String nameNorm = nameKey(name);
  late final String companyNorm = companyKey(company);
  late final Set<String> locals = {for (final e in emails) e.split('@').first};
  late final Set<String> domains = {
    for (final e in emails)
      if (e.contains('@') && !_freeMail.contains(e.split('@').last)) e.split('@').last,
  };
}

/// Webmail domains say nothing about the employer.
const _freeMail = {
  'gmail.com',
  'googlemail.com',
  'yahoo.com',
  'hotmail.com',
  'outlook.com',
  'live.com',
  'icloud.com',
  'me.com',
  'aol.com',
  'proton.me',
  'protonmail.com',
  'msn.com',
  'comcast.net',
};

enum MatchReason {
  mobile('Same mobile number'),
  nameEmail('Same name and email'),
  nameCompany('Same name, similar company');

  final String label;
  const MatchReason(this.label);
}

class DupMatch {
  final MatchReason reason;
  final double score; // 0..1, for ordering
  /// False when the two records are at different companies: probably the
  /// same person after a job change (S12), not a plain duplicate.
  final bool sameCompany;
  const DupMatch(this.reason, this.score, {required this.sameCompany});

  @override
  String toString() => 'DupMatch(${reason.name}, ${score.toStringAsFixed(2)}, sameCompany: $sameCompany)';
}

/// The match rule, in order: exact mobile; normalised name + same email local
/// part; normalised name + Jaro-Winkler >= 0.9 on company or email domain.
DupMatch? matchPair(MatchCandidate a, MatchCandidate b) {
  if (a.id == b.id) return null;
  final sameName = a.nameNorm.isNotEmpty && _sameName(a.nameNorm, b.nameNorm);
  final company = _companySimilarity(a, b);
  final same = company == null || company >= 0.9;

  if (a.mobiles.intersection(b.mobiles).isNotEmpty) {
    return DupMatch(MatchReason.mobile, sameName ? 1.0 : 0.95, sameCompany: same);
  }
  if (!sameName) return null;
  if (a.locals.intersection(b.locals).isNotEmpty) {
    return DupMatch(MatchReason.nameEmail, 0.9 + 0.05 * (company ?? 1), sameCompany: same);
  }
  if (company != null && company >= 0.9) {
    return DupMatch(MatchReason.nameCompany, 0.8 + 0.1 * company, sameCompany: true);
  }
  return null;
}

/// Equal keys, or the same first and last word ("dana k reyes" = "dana reyes").
bool _sameName(String a, String b) {
  if (a == b) return true;
  final x = a.split(' '), y = b.split(' ');
  return x.length > 1 && y.length > 1 && x.first == y.first && x.last == y.last;
}

/// Best Jaro-Winkler over company names and employer email domains; null when
/// either side has neither (nothing to compare).
double? _companySimilarity(MatchCandidate a, MatchCandidate b) {
  double? best;
  void consider(double s) => best = math.max(best ?? 0, s);
  if (a.companyNorm.isNotEmpty && b.companyNorm.isNotEmpty) consider(jaroWinkler(a.companyNorm, b.companyNorm));
  for (final x in a.domains) {
    for (final y in b.domains) {
      consider(jaroWinkler(x, y));
    }
  }
  return best;
}

/// Jaro-Winkler similarity, 0..1 (prefix scale 0.1, up to 4 characters).
double jaroWinkler(String s, String t) {
  if (s == t) return 1;
  if (s.isEmpty || t.isEmpty) return 0;
  final range = math.max(0, math.max(s.length, t.length) ~/ 2 - 1);
  final sm = List.filled(s.length, false), tm = List.filled(t.length, false);
  var matches = 0;
  for (var i = 0; i < s.length; i++) {
    final lo = math.max(0, i - range), hi = math.min(t.length - 1, i + range);
    for (var j = lo; j <= hi; j++) {
      if (tm[j] || s[i] != t[j]) continue;
      sm[i] = tm[j] = true;
      matches++;
      break;
    }
  }
  if (matches == 0) return 0;
  var k = 0, half = 0;
  for (var i = 0; i < s.length; i++) {
    if (!sm[i]) continue;
    while (!tm[k]) {
      k++;
    }
    if (s[i] != t[k]) half++;
    k++;
  }
  final m = matches.toDouble();
  final jaro = (m / s.length + m / t.length + (m - half / 2) / m) / 3;
  var prefix = 0;
  while (prefix < math.min(4, math.min(s.length, t.length)) && s[prefix] == t[prefix]) {
    prefix++;
  }
  return jaro + prefix * 0.1 * (1 - jaro);
}

/// A pair found by a library scan.
class DupPair {
  final MatchCandidate a, b;
  final DupMatch match;
  const DupPair(this.a, this.b, this.match);

  String get key => pairKey(a.id, b.id);
}

/// Order-independent key for a pair ("not a duplicate" memory).
String pairKey(String x, String y) => x.compareTo(y) < 0 ? '$x|$y' : '$y|$x';

/// Every matching pair in [people], best first, skipping [dismissed] keys.
/// Blocks on name key, first+last word and each mobile so it stays near-linear.
List<DupPair> findPairs(List<MatchCandidate> people, {Set<String> dismissed = const {}}) {
  final blocks = <String, List<MatchCandidate>>{};
  for (final p in people) {
    final words = p.nameNorm.split(' ');
    for (final key in {
      if (p.nameNorm.isNotEmpty) 'n:${words.first} ${words.last}',
      for (final m in p.mobiles) 'm:$m',
    }) {
      (blocks[key] ??= []).add(p);
    }
  }
  final seen = <String>{};
  final out = <DupPair>[];
  for (final group in blocks.values) {
    for (var i = 0; i < group.length; i++) {
      for (var j = i + 1; j < group.length; j++) {
        final key = pairKey(group[i].id, group[j].id);
        if (dismissed.contains(key) || !seen.add(key)) continue;
        final m = matchPair(group[i], group[j]);
        if (m != null) out.add(DupPair(group[i], group[j], m));
      }
    }
  }
  return out..sort((x, y) => y.match.score.compareTo(x.match.score));
}
