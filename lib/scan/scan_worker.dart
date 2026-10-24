import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import 'geometry.dart' show Quad;
import 'scan_pipeline.dart';
import 'sweep_tracker.dart' show sweepLog;

/// One capture waiting to be read.
class ScanJob {
  final Uint8List jpeg;
  final bool pile;
  final File? pending; // already saved (crash recovery re-uses it)
  final Object? tag; // who asked: a Sweep track id, so the result lands on that card

  /// Sweep: the tracked outline inside the crop, used if the edge search fails.
  final Quad? fallback;

  /// Sweep: where the crop sits in its still (cut-off is judged on the still).
  final ({int dx, int dy, int width, int height})? source;

  /// Sweep: this is the second try of a card whose first reading was garbled;
  /// whatever it reads is queued.
  final bool lastTry;
  const ScanJob(
    this.jpeg, {
    this.pile = false,
    this.pending,
    this.tag,
    this.fallback,
    this.source,
    this.lastTry = false,
  });
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

  /// Captures set aside in pending/failed/ after repeated failures this run.
  int setAside = 0;

  /// Told once per set-aside capture, so the app can say so.
  static void Function()? onSetAside;

  /// Told when a capture is skipped because the card is already captured.
  static void Function()? onAlreadyCaptured;

  /// Told after each capture is read: how many cards it added, and whether it was a pile.
  static void Function(int added, bool pile)? onJobDone;

  /// Told after each tagged capture is read (Sweep): cards added, cards that
  /// were already captured, whether reading failed, and captures dropped for
  /// reading as nothing (not a card).
  static void Function(Object tag, int added, int already, bool failed, int empty)? onTagged;

  /// Told just before [onTagged]: the queue ids this capture made (empty when it
  /// added none), so Sweep can check a repeat against rows that really exist and
  /// replace a junk entry.
  static void Function(Object tag, List<String> ids)? onTaggedIds;

  /// Told when a Sweep capture read as garbage and was not queued: the screen
  /// takes a fresh still and tries once more.
  static void Function(Object tag)? onSweepRetry;

  @override
  ScanWorkerState build() => const ScanWorkerState(0, 0);

  bool get full => _jobs.length >= maxQueued;

  /// Queues a capture. It is written to pending/ first, so a capture waiting
  /// its turn survives the app being killed (audit MOB-REL-0002).
  Future<void> add(ScanJob job) async {
    var j = job;
    if (j.pending == null) {
      final store = await ref.read(imageStoreProvider.future);
      j = ScanJob(
        job.jpeg,
        pile: job.pile,
        pending: await store.savePending(job.jpeg),
        tag: job.tag,
        fallback: job.fallback,
        source: job.source,
        lastTry: job.lastTry,
      );
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
        var added = 0, already = 0, empty = 0;
        var failed = false, retry = false;
        final madeIds = <String>[];
        try {
          final pipeline = await ref.read(scanPipelineProvider.future);
          final queue = await ref.read(cardQueueProvider.future);
          final contacts = ref.read(contactsRepoProvider);
          final autoSave = await ref.read(settingsRepoProvider).autoSaveClean();
          final (sides, pending) = await pipeline.processKeeping(
            job.jpeg,
            pile: job.pile,
            pending: job.pending,
            // A Sweep crop is a loose box around the card from a full still:
            // the edge search finds the card in it, every turn is tried.
            fallback: job.fallback,
            source: job.source,
            allTurns: job.tag != null,
          );
          // Sweep: a first reading that is garbage (no contact detail, no
          // believable name) is retaken once instead of queued.
          if (job.tag != null && !job.lastTry && sides.isNotEmpty && sides.every(isGarbled)) {
            retry = true;
            await (await ref.read(imageStoreProvider.future)).donePending(pending);
            sweepLog('track ${job.tag} read as garbage, taking a fresh still');
          }
          for (final side in retry ? const <ScannedSide>[] : sides) {
            // Sweep: a capture that read as nothing is not a card; drop it quietly.
            if (job.tag != null && !hasAnyField(side)) {
              empty++;
              continue;
            }
            // The same card shot again in this session is not queued twice (F39).
            // Sweep asks for a closer name match: a false "Already in queue" loses a card.
            final match = await queue.matchingCard(side, nameBar: job.tag == null ? 0.85 : 0.92);
            if (match != null) {
              if (job.tag == null) onAlreadyCaptured?.call();
              if (job.tag != null) sweepLog('track ${job.tag} repeats card ${match.$1} (${match.$2})');
              already++;
              continue;
            }
            final id = await queue.enqueue(side);
            madeIds.add(id);
            if (autoSave && isCleanCard(side)) {
              final person = await queue.autoSave(id, side, contacts);
              await ref.read(careerRepoProvider).checkNewCard(person);
            }
            added++;
          }
          // Every card from this capture is in the queue: the saved capture can go.
          await (await ref.read(imageStoreProvider.future)).donePending(pending);
        } catch (_) {
          failed = true;
          // A bad photo is skipped; the pending copy stays for the next recovery,
          // until it has failed ImageStore.maxTries times.
          final p = job.pending;
          if (p != null) {
            try {
              if (await (await ref.read(imageStoreProvider.future)).failedPending(p)) {
                setAside++;
                onSetAside?.call();
              }
            } catch (_) {}
          }
        }
        _jobs.removeAt(0);
        state = ScanWorkerState(_jobs.length, added);
        onJobDone?.call(added, job.pile);
        if (job.tag case final tag?) {
          if (retry) {
            onSweepRetry?.call(tag);
          } else {
            onTaggedIds?.call(tag, madeIds);
            onTagged?.call(tag, added, already, failed, empty);
          }
        }
      }
    } finally {
      _running = false;
    }
  }
}

final scanWorkerProvider = NotifierProvider<ScanWorker, ScanWorkerState>(ScanWorker.new);
