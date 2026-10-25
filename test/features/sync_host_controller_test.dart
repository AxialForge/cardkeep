import 'dart:io';

import 'package:card_organizer/app/providers.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/images/image_store.dart';
import 'package:card_organizer/core/sync/blob_transfer.dart';
import 'package:card_organizer/core/sync/image_blobs.dart';
import 'package:card_organizer/core/sync/net/sessions.dart';
import 'package:card_organizer/core/sync/net/sync_client.dart';
import 'package:card_organizer/core/sync/sync_engine.dart';
import 'package:card_organizer/features/sync/sync_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Plain tests, not widget tests: the widget binding turns every HttpClient into a 400.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('the host controller, for real', () {
    test('starts, shows a code, pairs a PC, and unpairs it', () async {
      final dir = await Directory.systemTemp.createTemp('ck_host');
      addTearDown(() => dir.delete(recursive: true));
      SyncHostController.overrides = SyncHostOverrides(
        bindTo: InternetAddress.loopbackIPv4,
        host: '127.0.0.1',
        certificateDir: () async => dir,
      );
      addTearDown(() => SyncHostController.overrides = null);
      final blobs = ImageBlobStore(ImageStore(Directory('${dir.path}/cards')));
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncBlobsProvider.overrideWith((ref) async => blobs),
          syncEngineProvider.overrideWith((ref) async => SyncEngine(db, blobs: blobs)),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(syncHostProvider, (_, _) {});
      addTearDown(sub.close);

      Future<void> until(bool Function(SyncHostState s) ok) async {
        for (var i = 0; i < 100; i++) {
          if (ok(container.read(syncHostProvider))) return;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        fail('Timed out: ${container.read(syncHostProvider).phase}');
      }

      await until((s) => s.phase == SyncHostPhase.ready && s.payload != null);
      final p = container.read(syncHostProvider).payload!;
      expect(p.host, '127.0.0.1');
      expect(container.read(syncHostProvider).peers, isEmpty);

      // A PC pairs with the code on the screen.
      final pcDb = AppDatabase(NativeDatabase.memory());
      addTearDown(pcDb.close);
      final client = SyncClient(
        engine: SyncEngine(pcDb),
        blobSource: MemoryBlobStore(),
        blobSink: MemoryBlobStore(),
        store: DbHostCredentialStore(pcDb),
        deviceName: 'Test PC',
      );
      await client.pair(p);
      await until((s) => s.peers.length == 1 && s.payload == null);
      expect(container.read(syncHostProvider).notice, contains('Test PC'));

      // Unpairing from the phone drops the PC and shows a new code.
      await container.read(syncHostProvider.notifier).unpair(container.read(syncHostProvider).peers.single.id);
      await until((s) => s.peers.isEmpty && s.payload != null);
      await expectLater(client.sync(), throwsA(isA<SyncException>().having((e) => e.code, 'code', 'unauthorized')));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
