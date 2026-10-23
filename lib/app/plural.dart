import 'package:intl/intl.dart';

/// "1 person", "3 people", "1,204 cards": a count with the right word form.
/// [many] defaults to [one] plus "s".
String plural(int n, String one, [String? many]) =>
    '${NumberFormat.decimalPattern().format(n)} ${n == 1 ? one : (many ?? '${one}s')}';
