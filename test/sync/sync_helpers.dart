import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/sync/change_set.dart';
import 'package:card_organizer/core/sync/sync_engine.dart';
import 'package:card_organizer/core/sync/sync_tables.dart';
import 'package:card_organizer/core/tags/tags_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// True time, in seconds. Every node's clock is this plus its own skew, so a
/// test moves time with [advance] and gives a phone a wrong clock with [skew].
class World {
  int now;
  World([int? start]) : now = start ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600;
  void advance(int seconds) => now += seconds;
}

/// One device: its own in-memory database, engine and repositories.
class Node {
  final String name;
  final World world;
  final int skew;
  final AppDatabase db = AppDatabase(NativeDatabase.memory());
  late final SyncEngine engine;
  late final ContactsRepository contacts;
  late final TagsRepository tags;
  late final String id;

  Node(this.name, this.world, {this.skew = 0, Duration window = const Duration(minutes: 2), int pageSize = 5000}) {
    engine = SyncEngine(db, clock: _clock, conflictWindow: window, pageSize: pageSize);
    contacts = ContactsRepository(db, clock: _clock);
    tags = TagsRepository(db, contacts, clock: _clock);
  }

  DateTime _clock() => DateTime.fromMillisecondsSinceEpoch((world.now + skew) * 1000);

  /// This node's own clock, in seconds.
  int get t => world.now + skew;

  Future<void> init() async => id = await engine.myDeviceId();

  Future<void> close() => db.close();

  Future<String> person(String first, {String last = 'Reyes', String company = '', String notes = ''}) => contacts.save(
    ContactDraft(first: first, last: last, company: company, notes: notes, title: company.isEmpty ? '' : 'Buyer'),
  );

  /// Sets a column of a row by raw SQL, stamped at this node's [t] (or [at]).
  Future<void> set(String table, String key, Map<String, Object?> values, {int? at}) async {
    final spec = specOf(table);
    final cols = values.keys.toList();
    await db.customStatement(
      'UPDATE $table SET ${[for (final c in cols) '$c = ?'].join(', ')}, updated_at = ? WHERE ${spec.key} = ?',
      [...values.values, at ?? t, key],
    );
  }

  Future<void> tombstone(String table, String key, {int? at}) async {
    final spec = specOf(table);
    final s = at ?? t;
    await db.customStatement('UPDATE $table SET deleted_at = ?, updated_at = ? WHERE ${spec.key} = ?', [s, s, key]);
  }

  Future<Map<String, Object?>?> row(String table, String key) async {
    final spec = specOf(table);
    final r = await db
        .customSelect('SELECT * FROM $table WHERE ${spec.key} = ?', variables: [Variable.withString(key)])
        .getSingleOrNull();
    return r?.data;
  }

  Future<int> count(String sql) async => (await db.customSelect(sql).getSingle()).read<int>('n');
}

Future<(Node, Node)> pair({
  int skewB = 0,
  Duration window = const Duration(minutes: 2),
  int pageSize = 5000,
  int? start,
}) async {
  final w = World(start);
  final a = Node('A', w, window: window, pageSize: pageSize);
  final b = Node('B', w, skew: skewB, window: window, pageSize: pageSize);
  await a.init();
  await b.init();
  // The offset is the peer's clock minus ours.
  await a.engine.registerPeer(b.id, name: 'B', clockOffsetSeconds: skewB);
  await b.engine.registerPeer(a.id, name: 'A', clockOffsetSeconds: -skewB);
  return (a, b);
}

/// One way: [from] builds what [to] has not seen, [to] applies it, [from] is told.
Future<ApplyResult> send(Node from, Node to, {int? limit}) async {
  var cursor = null as String?;
  ApplyResult? last;
  do {
    final cs = await from.engine.buildChanges(peerId: to.id, cursor: cursor, limit: limit);
    last = await to.engine.apply(ChangeSet.decode(cs.encode()), clockOffset: null);
    await from.engine.acknowledge(to.id, cs, peerConflicts: last.conflicts);
    cursor = cs.next;
  } while (cursor != null);
  return last;
}

/// A full round: A -> B, then B -> A.
Future<void> exchange(Node a, Node b) async {
  await send(a, b);
  await send(b, a);
}

/// Every synced table, ordered, without the columns that legitimately differ
/// between devices (stamps).
Future<Map<String, List<Map<String, Object?>>>> dump(AppDatabase db, {bool stamps = false}) async {
  final out = <String, List<Map<String, Object?>>>{};
  for (final spec in syncTables) {
    final rows = await db.customSelect('SELECT * FROM ${spec.name} ORDER BY ${spec.key}').get();
    out[spec.name] = [
      for (final r in rows)
        {
          for (final e in r.data.entries)
            if (stamps || (e.key != 'updated_at' && e.key != 'created_at')) e.key: e.value,
        },
    ];
  }
  return out;
}

/// A short description of the first difference between two dumps, for failure messages.
String firstDiff(Map<String, List<Map<String, Object?>>> x, Map<String, List<Map<String, Object?>>> y) {
  for (final t in x.keys) {
    final a = x[t]!, b = y[t]!;
    if (a.length != b.length) return '$t: ${a.length} rows vs ${b.length}';
    for (var i = 0; i < a.length; i++) {
      for (final c in a[i].keys) {
        if (a[i][c] != b[i][c]) return '$t[$i].$c: ${a[i][c]} vs ${b[i][c]}';
      }
    }
  }
  return 'same';
}
