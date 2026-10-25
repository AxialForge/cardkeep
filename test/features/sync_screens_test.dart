import 'package:card_organizer/app/app.dart';
import 'package:card_organizer/app/providers.dart';
import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/sync/net/pairing.dart';
import 'package:card_organizer/core/sync/sync_engine.dart';
import 'package:card_organizer/features/sync/sync_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// A host controller that sits in a state the test chooses and starts nothing.
class _FakeHost extends SyncHostController {
  final SyncHostState initial;
  _FakeHost(this.initial);
  int newCodes = 0;
  int starts = 0;
  @override
  SyncHostState build() => initial;
  @override
  Future<void> start() async => starts++;
  @override
  Future<void> newCode() async => newCodes++;
}

SyncPeer peer({DateTime? last}) =>
    SyncPeer(id: 'pc-1', name: 'Joe\'s PC', theirWatermark: 0, myWatermark: 0, clockOffsetSeconds: 0, lastSyncAt: last);

PairingPayload payload() => PairingPayload(
  host: '192.168.1.20',
  port: 49152,
  token: 'tok',
  certSha256: 'a' * 64,
  deviceName: 'CardKeep on this phone',
);

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<_FakeHost> start(WidgetTester tester, SyncHostState state, {String at = '/sync', double text = 1}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = text;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final fake = _FakeHost(state);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          regionProvider.overrideWith((ref) => Stream.value('US')),
          syncHostProvider.overrideWith(() => fake),
          syncEngineProvider.overrideWith((ref) async => SyncEngine(db)),
        ],
        child: CardOrganizerApp(initialLocation: at, showOnboarding: false),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    return fake;
  }

  /// Database work finishes on the real clock but its timers run on the test clock, so alternate.
  Future<void> tapAndWait(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  group('the Sync screen', () {
    testWidgets('getting ready shows progress', (tester) async {
      await start(tester, const SyncHostState());
      expect(find.text('Sync to desktop'), findsWidgets);
      expect(find.text('Getting ready…'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('no Wi-Fi says so and offers to try again', (tester) async {
      final fake = await start(tester, const SyncHostState(phase: SyncHostPhase.noNetwork));
      expect(find.text('Not on Wi-Fi'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(fake.starts, 1);
      await finish(tester);
    });

    testWidgets('a failure shows the reason and offers to try again', (tester) async {
      await start(tester, const SyncHostState(phase: SyncHostPhase.failed, error: 'port busy'));
      expect(find.text('Could not start'), findsOneWidget);
      expect(find.textContaining('port busy'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a pairing code shows the QR, the address and a countdown', (tester) async {
      final fake = await start(
        tester,
        SyncHostState(
          phase: SyncHostPhase.ready,
          payload: payload(),
          codeExpiresAt: DateTime.now().add(const Duration(minutes: 1, seconds: 40)),
        ),
      );
      expect(find.byType(QrImageView), findsOneWidget);
      expect(PairingPayload.parse(payload().toQrText()).port, 49152);
      expect(find.text('Phone address 192.168.1.20:49152'), findsOneWidget);
      expect(find.textContaining('This code works for 1:'), findsOneWidget);
      expect(find.text('Copy code text'), findsOneWidget);
      await tester.tap(find.text('New code'));
      expect(fake.newCodes, 1);
      await finish(tester);
    });

    testWidgets('an expired code says so', (tester) async {
      await start(
        tester,
        SyncHostState(
          phase: SyncHostPhase.ready,
          payload: payload(),
          codeExpiresAt: DateTime.now().subtract(const Duration(seconds: 5)),
        ),
      );
      expect(find.text('This code has expired.'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a paired PC shows its name, when it last synced, and Unpair', (tester) async {
      await start(
        tester,
        SyncHostState(
          phase: SyncHostPhase.ready,
          peers: [peer(last: DateTime.now().subtract(const Duration(minutes: 5)))],
        ),
      );
      expect(find.text('Joe\'s PC'), findsOneWidget);
      expect(find.text('Synced 5 min ago'), findsOneWidget);
      expect(find.text('Unpair'), findsOneWidget);
      expect(find.text('Pair a different PC'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing, reason: 'no code while paired');
      await tester.tap(find.text('Unpair'));
      await tester.pumpAndSettle();
      expect(find.text('Unpair Joe\'s PC?'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('live activity and a notice show', (tester) async {
      await start(
        tester,
        SyncHostState(
          phase: SyncHostPhase.ready,
          peers: [peer()],
          activity: 'The PC is fetching changes from this phone…',
        ),
      );
      expect(find.text('The PC is fetching changes from this phone…'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('open conflicts show a banner that opens the list', (tester) async {
      await tester.runAsync(() async {
        final id = await ContactsRepository(db).save(ContactDraft(first: 'Ada', last: 'Reyes'));
        await db.customStatement(
          'INSERT INTO sync_conflicts (id, peer_id, table_name, row_key, field, mine_json, theirs_json, '
          'mine_updated_at, theirs_updated_at, detected_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          ['c1', 'pc-1', 'people', id, 'notes', '"phone says"', '"pc says"', 100, 110, 120],
        );
      });
      await start(tester, SyncHostState(phase: SyncHostPhase.ready, peers: [peer()]));
      expect(find.text('1 field changed on both devices'), findsOneWidget);
      await tester.tap(find.text('1 field changed on both devices'));
      await tester.pumpAndSettle();
      expect(find.text('Changed on both devices'), findsOneWidget);
      expect(find.text('Ada Reyes'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('phone says'), findsOneWidget);
      expect(find.text('pc says'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('troubleshooting help is there and leads to Export and backup', (tester) async {
      await start(tester, const SyncHostState(phase: SyncHostPhase.noNetwork));
      await tester.scrollUntilVisible(find.text('Trouble connecting?'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Trouble connecting?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('same Wi-Fi'), findsWidgets);
      expect(find.text('Open Export and backup'), findsOneWidget);
      await finish(tester);
    });

    for (final (name, state) in <(String, SyncHostState)>[
      ('starting', const SyncHostState()),
      ('no Wi-Fi', const SyncHostState(phase: SyncHostPhase.noNetwork)),
      ('a code', SyncHostState(phase: SyncHostPhase.ready, payload: payload(), codeExpiresAt: DateTime(2100))),
      (
        'a paired PC with activity',
        SyncHostState(
          phase: SyncHostPhase.ready,
          peers: [peer()],
          activity: 'The PC is sending changes to this phone…',
        ),
      ),
    ]) {
      testWidgets('$name at 200% text has no overflow', (tester) async {
        await start(tester, state, text: 2);
        expect(tester.takeException(), isNull);
        await finish(tester);
      });
    }
  });

  group('the drawer entry', () {
    testWidgets('Sync to desktop shows how many fields need a choice', (tester) async {
      await tester.runAsync(() async {
        final id = await ContactsRepository(db).save(ContactDraft(first: 'Ada', last: 'Reyes'));
        await db.customStatement(
          'INSERT INTO sync_conflicts (id, peer_id, table_name, row_key, field, mine_json, theirs_json, '
          'mine_updated_at, theirs_updated_at, detected_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          ['c1', 'pc-1', 'people', id, 'notes', '"a"', '"b"', 100, 110, 120],
        );
      });
      await start(tester, const SyncHostState(), at: '/');
      tester.view.physicalSize = const Size(1170, 3600);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      final tile = find.ancestor(of: find.text('Sync to desktop'), matching: find.byType(ListTile));
      expect(tile, findsOneWidget);
      expect(find.descendant(of: tile, matching: find.text('1')), findsOneWidget);
      await finish(tester);
    });
  });

  group('the conflict list', () {
    Future<void> seed(WidgetTester tester) => tester.runAsync(() async {
      final id = await ContactsRepository(db).save(ContactDraft(first: 'Ada', last: 'Reyes'));
      for (final (i, f) in ['notes', 'last'].indexed) {
        await db.customStatement(
          'INSERT INTO sync_conflicts (id, peer_id, table_name, row_key, field, mine_json, theirs_json, '
          'mine_updated_at, theirs_updated_at, detected_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          ['c$i', 'pc-1', 'people', id, f, '"phone $f"', '"pc $f"', 100, 110, 120],
        );
      }
    });

    testWidgets('lists each field with both values, grouped under the contact', (tester) async {
      await seed(tester);
      await start(tester, const SyncHostState(phase: SyncHostPhase.ready), at: '/sync/conflicts');
      await tester.pumpAndSettle();
      expect(find.text('Ada Reyes'), findsOneWidget);
      expect(find.text('phone notes'), findsOneWidget);
      expect(find.text('pc notes'), findsOneWidget);
      expect(find.text('phone last'), findsOneWidget);
      expect(find.text('Keep all this phone\'s'), findsOneWidget);
      expect(find.text('Use all the PC\'s'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('choosing the phone\'s value closes that field only', (tester) async {
      await seed(tester);
      await start(tester, const SyncHostState(phase: SyncHostPhase.ready), at: '/sync/conflicts');
      await tester.pumpAndSettle();
      await tapAndWait(tester, find.text('Keep this').first);
      final open = await tester.runAsync(() => SyncEngine(db).openConflictCount());
      expect(open, 1);
      await finish(tester);
    });

    testWidgets('use all the PC\'s asks first, then closes everything', (tester) async {
      await seed(tester);
      await start(tester, const SyncHostState(phase: SyncHostPhase.ready), at: '/sync/conflicts');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use all the PC\'s'));
      await tester.pumpAndSettle();
      expect(find.text('Use your PC\'s values?'), findsOneWidget);
      await tapAndWait(tester, find.text('Use the PC\'s'));
      final open = await tester.runAsync(() => SyncEngine(db).openConflictCount());
      expect(open, 0);
      expect(find.text('Nothing to choose'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('an empty list says so', (tester) async {
      await start(tester, const SyncHostState(phase: SyncHostPhase.ready), at: '/sync/conflicts');
      await tester.pumpAndSettle();
      expect(find.text('Nothing to choose'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('at 200% text there is no overflow', (tester) async {
      await seed(tester);
      await start(tester, const SyncHostState(phase: SyncHostPhase.ready), at: '/sync/conflicts', text: 2);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  });
}
