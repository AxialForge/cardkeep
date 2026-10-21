import 'package:card_organizer/core/dupes/matcher.dart';
import 'package:flutter_test/flutter_test.dart';

var _n = 0;

MatchCandidate p(String name, {String company = '', List<String> mobiles = const [], List<String> emails = const []}) =>
    MatchCandidate(id: 'p${_n++}', name: name, company: company, mobiles: {...mobiles}, emails: {...emails});

/// (a, b, expected reason or null, sameCompany)
typedef Row = (MatchCandidate, MatchCandidate, MatchReason?, bool?);

void main() {
  final rows = <String, Row>{
    // Rule 1: exact mobile.
    'same mobile, same name': (
      p('Dana Reyes', mobiles: ['+13305550142']),
      p('Dana Reyes', mobiles: ['+13305550142']),
      MatchReason.mobile,
      true,
    ),
    'same mobile, nickname': (
      p('Bill Ortiz', company: 'Halden', mobiles: ['+13305550142']),
      p('William Ortiz', company: 'Halden', mobiles: ['+13305550142']),
      MatchReason.mobile,
      true,
    ),
    'same mobile, new company': (
      p('Dana Reyes', company: 'Halden Tooling', mobiles: ['+13305550142']),
      p('Dana Reyes', company: 'Brightline', mobiles: ['+13305550142']),
      MatchReason.mobile,
      false,
    ),
    'one of two mobiles shared': (p('A B', mobiles: ['+1', '+2']), p('C D', mobiles: ['+2']), MatchReason.mobile, true),
    'different mobiles': (
      p('Dana Reyes', mobiles: ['+13305550142']),
      p('Sam Okafor', mobiles: ['+13305550199']),
      null,
      null,
    ),
    // Rule 2: name + email local part.
    'same email': (
      p('Dana Reyes', emails: ['dreyes@halden.com']),
      p('Dana Reyes', emails: ['dreyes@halden.com']),
      MatchReason.nameEmail,
      true,
    ),
    'same local, new domain': (
      p('Dana Reyes', company: 'Halden', emails: ['dreyes@halden.com']),
      p('Dana Reyes', company: 'Brightline', emails: ['dreyes@brightline.io']),
      MatchReason.nameEmail,
      false,
    ),
    'same local, gmail vs work': (
      p('Dana Reyes', emails: ['dreyes@gmail.com']),
      p('Dana Reyes', emails: ['dreyes@halden.com']),
      MatchReason.nameEmail,
      true,
    ),
    'name case and punctuation': (
      p('DANA  REYES.', emails: ['d@gmail.com']),
      p('dana reyes', emails: ['d@yahoo.com']),
      MatchReason.nameEmail,
      true,
    ),
    'middle initial': (
      p('Dana K. Reyes', emails: ['dana@x.com']),
      p('Dana Reyes', emails: ['dana@x.com']),
      MatchReason.nameEmail,
      true,
    ),
    'same local, different name': (
      p('Dana Reyes', emails: ['info@halden.com']),
      p('Sam Okafor', emails: ['info@halden.com']),
      null,
      null,
    ),
    'different locals': (p('Dana Reyes', emails: ['dana@x.com']), p('Dana Reyes', emails: ['reyes@y.com']), null, null),
    // Rule 3: name + similar company or domain.
    'same company': (
      p('Dana Reyes', company: 'Halden Tooling'),
      p('Dana Reyes', company: 'Halden Tooling'),
      MatchReason.nameCompany,
      true,
    ),
    'legal suffix': (
      p('Dana Reyes', company: 'Halden Tooling, Inc.'),
      p('Dana Reyes', company: 'Halden Tooling LLC'),
      MatchReason.nameCompany,
      true,
    ),
    'company typo': (
      p('Dana Reyes', company: 'Halden Toolng'),
      p('Dana Reyes', company: 'Halden Tooling'),
      MatchReason.nameCompany,
      true,
    ),
    'ampersand': (
      p('Dana Reyes', company: 'Smith & Sons'),
      p('Dana Reyes', company: 'Smith and Sons'),
      MatchReason.nameCompany,
      true,
    ),
    'same domain, no company': (
      p('Dana Reyes', emails: ['dana@halden.com']),
      p('Dana Reyes', emails: ['d.reyes@halden.com']),
      MatchReason.nameCompany,
      true,
    ),
    'domain close to domain': (
      p('Dana Reyes', emails: ['dana@haldentool.com']),
      p('Dana Reyes', emails: ['d.reyes@haldentools.com']),
      MatchReason.nameCompany,
      true,
    ),
    'name only, no company': (p('Dana Reyes'), p('Dana Reyes'), null, null),
    'name, one company missing': (p('Dana Reyes', company: 'Halden'), p('Dana Reyes'), null, null),
    'same name, other company': (
      p('Dana Reyes', company: 'Halden Tooling'),
      p('Dana Reyes', company: 'Orbit Medical'),
      null,
      null,
    ),
    'gmail domains ignored': (
      p('Dana Reyes', emails: ['a@gmail.com']),
      p('Dana Reyes', emails: ['b@gmail.com']),
      null,
      null,
    ),
    'different first names': (p('Dana Reyes', company: 'Halden'), p('Diana Reyes', company: 'Halden'), null, null),
    'different last names': (p('Dana Reyes', company: 'Halden'), p('Dana Rees', company: 'Halden'), null, null),
    'single-word names differ': (p('Dana', company: 'Halden'), p('Dana Reyes', company: 'Halden'), null, null),
    'single-word same name': (
      p('Dana', company: 'Halden'),
      p('Dana', company: 'Halden'),
      MatchReason.nameCompany,
      true,
    ),
    'accents kept': (p('José Ruiz', company: 'Ruiz SA'), p('Jose Ruiz', company: 'Ruiz SA'), null, null),
    'empty names': (p('', company: 'Halden'), p('', company: 'Halden'), null, null),
    'mobile beats name': (
      p('Front Desk', mobiles: ['+15'], company: 'A'),
      p('Dana Reyes', mobiles: ['+15'], company: 'A'),
      MatchReason.mobile,
      true,
    ),
    'email wins over company check': (
      p('Dana Reyes', company: 'A Corp', emails: ['dana@a.com']),
      p('Dana Reyes', company: 'Zeta', emails: ['dana@zeta.com']),
      MatchReason.nameEmail,
      false,
    ),
  };

  test('30 table pairs', () => expect(rows.length, 30));

  for (final MapEntry(key: name, value: (a, b, reason, same)) in rows.entries) {
    test(name, () {
      final m = matchPair(a, b);
      expect(m?.reason, reason, reason: '$m');
      if (same != null) expect(m!.sameCompany, same);
      // Symmetric.
      expect(matchPair(b, a)?.reason, reason);
    });
  }

  test('jaroWinkler known values', () {
    expect(jaroWinkler('martha', 'marhta'), closeTo(0.961, 0.001));
    expect(jaroWinkler('dwayne', 'duane'), closeTo(0.84, 0.001));
    expect(jaroWinkler('abc', 'abc'), 1);
    expect(jaroWinkler('abc', ''), 0);
  });

  test('findPairs blocks, skips dismissed, sorts best first', () {
    final a = MatchCandidate(id: 'a', name: 'Dana Reyes', company: 'Halden', mobiles: {'+1'});
    final b = MatchCandidate(id: 'b', name: 'Dana Reyes', company: 'Halden');
    final c = MatchCandidate(id: 'c', name: 'Someone Else', mobiles: {'+1'});
    final d = MatchCandidate(id: 'd', name: 'Sam Okafor');
    final all = findPairs([a, b, c, d]);
    expect([for (final x in all) x.key], ['a|c', 'a|b']);
    expect(findPairs([a, b, c, d], dismissed: {'a|c'}).map((x) => x.key), ['a|b']);
  });
}
