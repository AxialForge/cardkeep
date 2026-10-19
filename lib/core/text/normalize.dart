/// Matching keys. Stored next to the printed value, never shown.
library;

final _legalSuffix = RegExp(
    r'\b(inc|incorporated|llc|l l c|ltd|limited|corp|corporation|co|company|gmbh|ag|plc|lp|llp|sa|srl|pty|group|holdings)\b',
    caseSensitive: false);

/// "Halden Tooling Group, Inc." -> "halden tooling"
String companyKey(String name) {
  var s = name.toLowerCase().replaceAll('&', ' and ').replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), ' ');
  s = s.replaceAll(_legalSuffix, ' ');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Lower case, accents kept, punctuation and repeated spaces removed.
String nameKey(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');
