import 'package:card_organizer/core/followups/followups_repository.dart';
import 'package:card_organizer/core/followups/reminders.dart';
import 'package:flutter_test/flutter_test.dart';

FollowupItem item(String id, DateTime due) => FollowupItem(personId: id, name: id, first: id, due: due);

void main() {
  final now = DateTime(2026, 10, 22, 23, 2);

  test('a future follow-up reminds at its time', () {
    final due = DateTime(2026, 10, 23, 8);
    expect(Reminders.plan([item('a', due)], now, {}).single.$2, due);
  });

  test('due earlier today: a catch-up reminder a minute from now, once (phone test F31)', () {
    final f = item('a', DateTime(2026, 10, 22, 8));
    expect(Reminders.plan([f], now, {}).single.$2, now.add(const Duration(minutes: 1)));
    expect(Reminders.plan([f], now, {'a|2026-10-22'}), isEmpty, reason: 'already caught up today');
  });

  test('overdue from an earlier day: no reminder', () {
    expect(Reminders.plan([item('a', DateTime(2026, 10, 20, 8))], now, {}), isEmpty);
  });
}
