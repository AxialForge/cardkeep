import 'package:card_organizer/scan/geometry.dart';
import 'package:card_organizer/scan/sweep_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 3.5 x 2 card-shaped quad with its top-left at (x, y), 175 x 100 px.
Quad card(double x, double y) => Quad([Pt(x, y), Pt(x + 175, y), Pt(x + 175, y + 100), Pt(x, y + 100)]);

const w = 480.0, h = 640.0;

void main() {
  late SweepTracker tr;
  late DateTime t0;
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  setUp(() {
    tr = SweepTracker();
    t0 = DateTime(2026, 10, 23, 12);
  });

  test('each card keeps its id while the phone moves', () {
    tr.update([card(40, 60), card(260, 300)], [100, 100], width: w, height: h, now: at(0));
    final ids = tr.tracks.map((t) => t.id).toList();
    // The phone moves: everything shifts 30 px up-left, in the other order.
    tr.update([card(230, 270), card(10, 30)], [100, 100], width: w, height: h, now: at(200));
    expect(tr.tracks.length, 2);
    expect(tr.tracks.map((t) => t.id).toList(), ids, reason: 'no new tracks for moved cards');
    expect(tr.tracks.first.quad.tl.x, 10);
  });

  test('a card is captured only after it is steady for 300 ms', () {
    tr.update([card(40, 60)], [100], width: w, height: h, now: at(0));
    expect(tr.next(width: w, height: h, now: at(0)), isNull);
    tr.update([card(41, 60)], [100], width: w, height: h, now: at(200));
    expect(tr.next(width: w, height: h, now: at(200)), isNull);
    tr.update([card(41, 61)], [100], width: w, height: h, now: at(320));
    expect(tr.next(width: w, height: h, now: at(320))?.id, tr.tracks.single.id);
  });

  test('movement restarts the steady clock', () {
    tr.update([card(40, 60)], [100], width: w, height: h, now: at(0));
    tr.update([card(80, 60)], [100], width: w, height: h, now: at(250)); // moved 40 px
    tr.update([card(80, 60)], [100], width: w, height: h, now: at(400));
    expect(
      tr.next(width: w, height: h, now: at(400)),
      isNull,
      reason: 'only 150 ms since it moved',
    );
    tr.update([card(80, 60)], [100], width: w, height: h, now: at(600));
    expect(tr.next(width: w, height: h, now: at(600)), isNotNull);
  });

  test('a blurry card waits, then is captured anyway after the soft limit', () {
    tr.update([card(40, 60)], [10], width: w, height: h, now: at(0));
    tr.update([card(40, 60)], [10], width: w, height: h, now: at(400));
    expect(tr.next(width: w, height: h, now: at(400)), isNull);
    tr.update([card(40, 60)], [10], width: w, height: h, now: at(950));
    expect(tr.next(width: w, height: h, now: at(950)), isNotNull);
  });

  test('a card cut off at the edge is not captured', () {
    tr.update([card(0, 60)], [100], width: w, height: h, now: at(0));
    tr.update([card(0, 60)], [100], width: w, height: h, now: at(500));
    expect(tr.next(width: w, height: h, now: at(500)), isNull);
  });

  test('never twice: reading and done cards are not returned again', () {
    tr.update([card(40, 60)], [100], width: w, height: h, now: at(0));
    tr.update([card(40, 60)], [100], width: w, height: h, now: at(400));
    final t = tr.next(width: w, height: h, now: at(400))!;
    tr.markReading(t.id);
    tr.update([card(40, 60)], [100], width: w, height: h, now: at(800));
    expect(tr.next(width: w, height: h, now: at(800)), isNull);
    tr.markDone(t.id);
    tr.markDone(t.id); // a second result for the same card is ignored
    tr.update([card(40, 60)], [100], width: w, height: h, now: at(5000));
    expect(tr.next(width: w, height: h, now: at(5000)), isNull);
    expect(tr.doneCount, 1);
    expect(tr.tracks.single.state, SweepState.done);
  });

  test('a missed card is retried after a pause, at most three times', () {
    tr.update([card(40, 60)], [100], width: w, height: h, now: at(0));
    var now = 400;
    for (var i = 0; i < 3; i++) {
      tr.update([card(40, 60)], [100], width: w, height: h, now: at(now));
      final t = tr.next(width: w, height: h, now: at(now));
      expect(t, isNotNull, reason: 'try ${i + 1}');
      tr.markReading(t!.id);
      tr.markMissed(t.id, at(now));
      expect(
        tr.next(width: w, height: h, now: at(now + 100)),
        isNull,
        reason: 'waits before retrying',
      );
      now += 2500;
    }
    tr.update([card(40, 60)], [100], width: w, height: h, now: at(now));
    expect(
      tr.next(width: w, height: h, now: at(now)),
      isNull,
      reason: 'gave up after 3 tries',
    );
  });

  test('counter: done cards stay counted after they leave the view', () {
    tr.update([card(40, 60), card(260, 300)], [100, 100], width: w, height: h, now: at(0));
    tr.markDone(tr.tracks.first.id);
    expect((tr.doneCount, tr.total), (1, 2));
    // The done card leaves the view and is forgotten; a new one comes in.
    tr.update([card(260, 300), card(40, 450)], [100, 100], width: w, height: h, now: at(2000));
    expect((tr.doneCount, tr.total), (1, 3));
  });

  test('a card being read keeps its track out of view so its result lands', () {
    tr.update([card(40, 60)], [100], width: w, height: h, now: at(0));
    tr.update([card(40, 60)], [100], width: w, height: h, now: at(400));
    final t = tr.next(width: w, height: h, now: at(400))!;
    tr.markReading(t.id);
    tr.update([], [], width: w, height: h, now: at(5000));
    expect(tr.byId(t.id), isNotNull);
    tr.markDone(t.id);
    expect(tr.doneCount, 1);
  });
}
