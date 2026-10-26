import 'package:flutter_test/flutter_test.dart';

import 'sync_helpers.dart';

/// The display order of the built-in place categories belongs to each device:
/// after a restore it differed between the phone and the PC and raised four
/// "changed on both devices" entries. A category the owner added still syncs
/// its order.
void main() {
  late Node a, b;

  setUp(() async {
    final p = await pair();
    a = p.$1;
    b = p.$2;
  });
  tearDown(() async {
    await a.close();
    await b.close();
  });

  Future<int> sortOf(Node n, String id) async => (await n.row('place_categories', id))!['sort'] as int;

  test('different orders of a built-in category on the two devices raise no conflict and stay as they are', () async {
    await exchange(a, b); // both start from the same seeds
    a.world.advance(60);
    await a.set('place_categories', 'store', {'sort': 5});
    await b.set('place_categories', 'store', {'sort': 9}); // within the 2-minute window
    await a.set('place_categories', 'restaurant', {'sort': 1});
    await b.set('place_categories', 'restaurant', {'sort': 3});
    a.world.advance(5);
    await exchange(a, b);
    await exchange(b, a);
    expect(await a.engine.openConflictCount(), 0);
    expect(await b.engine.openConflictCount(), 0);
    expect(await sortOf(a, 'store'), 5);
    expect(await sortOf(b, 'store'), 9);
    expect(await sortOf(a, 'restaurant'), 1);
    expect(await sortOf(b, 'restaurant'), 3);
  });

  test('a change of a built-in category order alone is not carried over, far apart in time or not', () async {
    await exchange(a, b);
    a.world.advance(3600);
    await a.set('place_categories', 'vendor', {'sort': 42});
    a.world.advance(3600);
    await exchange(a, b);
    expect(await sortOf(b, 'vendor'), isNot(42));
    expect(await b.engine.openConflictCount(), 0);
  });

  test('other fields of a built-in category still merge and still conflict', () async {
    await exchange(a, b);
    a.world.advance(60);
    await a.set('place_categories', 'service', {'label': 'Services'});
    await b.set('place_categories', 'service', {'label': 'Trades'});
    a.world.advance(5);
    await exchange(a, b);
    final open = await b.engine.conflicts();
    expect(open.map((c) => c.field), ['label'], reason: 'the label conflicts; the order never does');
  });

  test('a category the owner added keeps syncing its order', () async {
    await a.db.customStatement("INSERT INTO place_categories (id, label, sort) VALUES ('c_bake', 'Bakery', 7)");
    a.world.advance(5);
    await exchange(a, b);
    expect(await sortOf(b, 'c_bake'), 7);
    a.world.advance(3600);
    await a.set('place_categories', 'c_bake', {'sort': 8});
    a.world.advance(5);
    await exchange(a, b);
    expect(await sortOf(b, 'c_bake'), 8);

    // And a change on both within the window is still a conflict.
    a.world.advance(3600);
    await a.set('place_categories', 'c_bake', {'sort': 1});
    await b.set('place_categories', 'c_bake', {'sort': 2});
    a.world.advance(5);
    await exchange(a, b);
    expect((await b.engine.conflicts()).map((c) => '${c.rowKey}.${c.field}'), ['c_bake.sort']);
  });

  test('conflicts about a built-in order raised by earlier builds are closed at the next sync', () async {
    await exchange(a, b);
    await b.db.customStatement(
      'INSERT INTO sync_conflicts (id, peer_id, table_name, row_key, field, mine_json, theirs_json, '
      "mine_updated_at, theirs_updated_at, detected_at) VALUES ('old-1', '${a.id}', 'place_categories', 'store', "
      "'sort', '2', '0', 1, 2, 3), ('old-2', '${a.id}', 'place_categories', 'c_bake', 'sort', '2', '0', 1, 2, 3)",
    );
    // c_bake exists on B as the owner's own category.
    await b.db.customStatement("INSERT INTO place_categories (id, label, sort) VALUES ('c_bake', 'Bakery', 7)");
    expect(await b.engine.openConflictCount(), 2);
    a.world.advance(5);
    await exchange(a, b);
    final open = await b.engine.conflicts();
    expect(open.map((c) => c.rowKey), ['c_bake'], reason: 'the built-in one is closed, the owner\'s category stays');
  });
}
