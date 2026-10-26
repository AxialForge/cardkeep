import 'dart:async';
import 'dart:io';

import 'package:card_organizer/app/providers.dart';
import 'package:card_organizer/core/contacts/contact_models.dart';
import 'package:card_organizer/core/contacts/contacts_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/images/image_store.dart';
import 'package:card_organizer/core/sync/change_set.dart';
import 'package:card_organizer/core/sync/image_blobs.dart';
import 'package:card_organizer/core/sync/sync_engine.dart';
import 'package:card_organizer/features/sync/desktop_sync.dart';
import 'package:card_organizer/features/sync/sync_providers.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Plain tests, not widget tests: the widget binding turns every HttpClient into a 400.
void main() {
  // Two databases on purpose: a phone and a PC.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase phoneDb;
  late AppDatabase pcDb;
  late ProviderContainer phone;
  late ProviderContainer pc;

  Future<void> until(bool Function() ok, String what) async {
    for (var i = 0; i < 100; i++) {
      if (ok()) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    fail('Timed out waiting for $what');
  }

  Future<List<String>> pcNames() async {
    final list = await ContactsRepository(pcDb).watchContacts(const ContactFilter()).first;
    return [for (final c in list) c.displayName];
  }

  /// The phone, listening on loopback, and the PC with its own database.
  setUp(() async {
    phoneDb = AppDatabase(NativeDatabase.memory());
    pcDb = AppDatabase(NativeDatabase.memory());
    final dir = await Directory.systemTemp.createTemp('ck_pc_sync');
    addTearDown(() => dir.delete(recursive: true));
    SyncHostController.overrides = SyncHostOverrides(
      bindTo: InternetAddress.loopbackIPv4,
      host: '127.0.0.1',
      certificateDir: () async => dir,
    );
    addTearDown(() => SyncHostController.overrides = null);
    await ContactsRepository(phoneDb).save(ContactDraft(first: 'Priya', last: 'Nambiar', company: 'Brightline'));

    ProviderContainer rig(AppDatabase db, String images) {
      final blobs = ImageBlobStore(ImageStore(Directory('${dir.path}/$images')));
      return ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncBlobsProvider.overrideWith((ref) async => blobs),
          syncEngineProvider.overrideWith((ref) async => SyncEngine(db, blobs: blobs)),
        ],
      );
    }

    phone = rig(phoneDb, 'phone_cards');
    pc = rig(pcDb, 'pc_cards');
    addTearDown(phone.dispose);
    addTearDown(pc.dispose);
    final sub = phone.listen(syncHostProvider, (_, _) {});
    addTearDown(sub.close);
    final pcSub = pc.listen(desktopSyncProvider, (_, _) {});
    addTearDown(pcSub.close);
    addTearDown(phoneDb.close);
    addTearDown(pcDb.close);
    await until(() => phone.read(syncHostProvider).payload != null, 'the phone to show a code');
    await until(() => pc.read(desktopSyncProvider).loaded, 'the PC to load');
  });

  String code() => phone.read(syncHostProvider).payload!.toQrText();
  DesktopSyncController pcSync() => pc.read(desktopSyncProvider.notifier);
  DesktopSyncState pcState() => pc.read(desktopSyncProvider);

  group('the Windows sync client, against a real phone host', () {
    test('a pasted code pairs, syncs the phone contacts across, and unpairing stops it', () async {
      expect(pcState().paired, isFalse);
      await pcSync().pair(code());
      expect(pcState().error, isNull, reason: pcState().error);
      expect(pcState().paired, isTrue);
      expect(pcState().notice, contains('Paired'));
      expect(pcState().last, isNotNull, reason: 'pairing ends with a first sync');
      expect(await pcNames(), ['Priya Nambiar']);

      // A change on the phone arrives on the next Sync now; one made here goes the other way.
      await ContactsRepository(phoneDb).save(ContactDraft(first: 'Sam', last: 'Okafor'));
      await ContactsRepository(pcDb).save(ContactDraft(first: 'Lena', last: 'Voss'));
      await pcSync().syncNow();
      expect(pcState().error, isNull, reason: pcState().error);
      expect(await pcNames(), containsAll(['Priya Nambiar', 'Sam Okafor', 'Lena Voss']));
      final onPhone = await ContactsRepository(phoneDb).watchContacts(const ContactFilter()).first;
      expect(onPhone.map((c) => c.displayName), contains('Lena Voss'));

      // The pairing survives a restart: a fresh controller finds the phone again.
      pc.invalidate(desktopSyncProvider);
      pc.listen(desktopSyncProvider, (_, _) {});
      await until(() => pcState().loaded, 'the PC to reload');
      expect(pcState().paired, isTrue);
      expect(pcState().host!.hostName, isNotEmpty);

      await pcSync().unpair();
      expect(pcState().paired, isFalse);
      expect(pcState().notice, contains('Unpaired'));
      await until(() => phone.read(syncHostProvider).peers.isEmpty, 'the phone to drop the PC');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a code can only be used once', () async {
      final text = code();
      await pcSync().pair(text);
      expect(pcState().paired, isTrue);
      await pcSync().unpair();

      await pcSync().pair(text);
      expect(pcState().paired, isFalse);
      expect(pcState().error, contains('expired or was already used'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('text that is not a pairing code is refused with a plain message', () async {
      await pcSync().pair('hello there');
      expect(pcState().paired, isFalse);
      expect(pcState().busy, isFalse);
      expect(pcState().error, 'That is not a CardKeep pairing code.');
      await pcSync().pair('cardkeep-sync:%%%');
      expect(pcState().error, 'That pairing code is damaged.');
    });

    test('Sync now before pairing does nothing', () async {
      await pcSync().syncNow();
      expect(pcState().busy, isFalse);
      expect(pcState().last, isNull);
      expect(pcState().error, isNull);
    });

    test('the automatic interval is remembered', () async {
      expect(pcState().autoMinutes, 10);
      await pcSync().setAutoMinutes(30);
      expect(pcState().autoMinutes, 30);
      expect(await ref0(pc).syncAutoMinutes(), 30);
      expect(autoSyncChoices, contains(0));
    });
  });

  group('what a person is told when it goes wrong', () {
    test('network failures all say how to get back in touch', () {
      for (final e in [TimeoutException('x'), const SocketException('x'), const HandshakeException('x')]) {
        expect(syncErrorText(e), contains('Sync to desktop'));
      }
    });

    test('the sync errors speak for themselves', () {
      expect(
        syncErrorText(const SyncFormatException('That pairing code is damaged.')),
        'That pairing code is damaged.',
      );
      expect(syncErrorText(StateError('boom')), startsWith('Something went wrong'));
    });
  });
}

/// The settings repository of a container, for reading back what the controller stored.
dynamic ref0(ProviderContainer c) => c.read(settingsRepoProvider);
