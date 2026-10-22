import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import 'scan_pipeline.dart';

/// One capture waiting to be read.
class ScanJob {
  final Uint8List jpeg;
  final bool pile;
  final File? pending; // already saved (crash recovery re-uses it)
  const ScanJob(this.jpeg, {this.pile = false, this.pending});
}

class ScanWorkerState {
  final int reading; // captures waiting or being read
  final int lastAdded; // cards added to the queue by the most recent job
  const ScanWorkerState(this.reading, this.lastAdded);
}

/// Batch reading (deep dive §2.11): captures queue up here while the camera
/// keeps going; each is read in turn, stored in the review queue, and saved
/// straight to Contacts when it's clean and auto-save is on.
class ScanWorker extends Notifier<ScanWorkerState> {
  static const maxQueued = 8;
  final _jobs = <ScanJob>[];
  bool _running = false;

  @override
  ScanWorkerState build() => const ScanWorkerState(0, 0);

  bool get full => _jobs.length >= maxQueued;

  /// Queues a capture. It is written to pending/ first, so a capture waiting
  /// its turn survives the app being killed (audit MOB-REL-0002).
  Future<void> add(ScanJob job) async {
    var j = job;
    if (j.pending == null) {
      final store = await ref.read(imageStoreProvider.future);
      j = ScanJob(job.jpeg, pile: job.pile, pending: await store.savePending(job.jpeg));
    }
    _jobs.add(j);
    state = ScanWorkerState(_jobs.length, state.lastAdded);
    unawaited(_run());
  }

  /// Captures left unprocessed by a crash or force-close.
  Future<int> recover() async {
    final store = await ref.read(imageStoreProvider.future);
    final orphans = store.orphanedPending();
    for (final f in orphans) {
      await add(ScanJob(await f.readAsBytes(), pending: f));
    }
    return orphans.length;
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    try {
      while (_jobs.isNotEmpty) {
        final job = _jobs.first;
        var added = 0;
        try {
          final pipeline = await ref.read(scanPipelineProvider.future);
          final queue = await ref.read(cardQueueProvider.future);
          final contacts = ref.read(contactsRepoProvider);
          final autoSave = await ref.read(settingsRepoProvider).autoSaveClean();
          final (sides, pending) = await pipeline.processKeeping(job.jpeg, pile: job.pile, pending: job.pending);
          for (final side in sides) {
            final id = await queue.enqueue(side);
            if (autoSave && isCleanCard(side)) {
              final person = await queue.autoSave(id, side, contacts);
              await ref.read(careerRepoProvider).checkNewCard(person);
            }
            added++;
          }
          // Every card from this capture is in the queue: the saved capture can go.
          await (await ref.read(imageStoreProvider.future)).donePending(pending);
        } catch (_) {
          // A bad photo is skipped; the pending copy (if any) stays for the next recovery.
        }
        _jobs.removeAt(0);
        state = ScanWorkerState(_jobs.length, added);
      }
    } finally {
      _running = false;
    }
  }
}

final scanWorkerProvider = NotifierProvider<ScanWorker, ScanWorkerState>(ScanWorker.new);
