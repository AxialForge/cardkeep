---
finding_id: MOB-REL-0002
audit_domain: 11
platform: android
severity: S3
blockers: [data-loss]
title: Queued scan captures exist only in memory; killing the app during batch scanning loses them
status: fixed-verified
confidence: high
evidence_basis: static
affected_component: lib/scan/scan_worker.dart:36-41, lib/features/scan/scan_screen.dart:240 and 307, lib/scan/scan_pipeline.dart:122-134, lib/core/images/image_store.dart:55
affected_screen: Scan (camera and gallery import), Review queue
affected_version: 0.6.0 (2010) cdcf49d
---

**Description.** The scanner accepts up to 8 captures ahead of the reader (`ScanWorker.maxQueued`). `scan_screen.dart:240` and `:307` call `worker.add(ScanJob(bytes))` with no `pending` file. The crash-safe copy is only written by `ScanPipeline.process` (`scan_pipeline.dart:122`) once the job reaches the head of the queue. On top of that, `ImageStore.commit` deletes the pending copy (`image_store.dart:55`) *before* OCR, QR, logo extraction and `queue.enqueue` run (`scan_pipeline.dart:132-134`, `scan_worker.dart:65`). ML Kit OCR takes seconds per card.

The stated contract ("never lose a capture", `image_store.dart:30-31`, `app.dart:44-45`) therefore fails in two windows:
1. Every capture still waiting in `_jobs` (up to 7) has no file on disk.
2. The capture being read has already lost its pending file and has no `cards` row yet. Its images are left orphaned in `cards/`, and nothing references them.

Severity is S3 rather than S4 because the paper card can usually be scanned again. At an event, though, the loss is silent and the card may already have been handed back.

**Preconditions.** Several captures queued ("Reading N" above 1), or a capture being read.

**Steps to reproduce.**
1. Batch-scan or gallery-import 5 or more cards quickly.
2. While "Reading N" shows, swipe the app away from Recents (or let the OS kill it).
3. Reopen the app. Start-up recovery reads at most the one file still in `pending/`. The other captures are gone, and no message says so.

**Expected.** Every accepted capture is on disk before it is acknowledged. The pending copy is deleted only after the `cards` row is committed.

**Observed (code).** Recovery (`scan_worker.dart:44-50`) can only find files in `pending/`, and queued jobs never reach `pending/` before they are processed.

**Root cause.** `savePending` runs in the pipeline instead of at capture time. The pending copy is removed during the image commit instead of after the enqueue.

**Remediation.** Call `store.savePending` in `ScanWorker.add` (or in scan_screen before `add`) and pass it as `pending`. Delete the pending copy only after `queue.enqueue` succeeds.

**Verification.** Test 1: queue 3 jobs behind a blocking fake pipeline and assert that 3 files exist in `pending/`. Test 2: throw after `commit` and before `enqueue`, and assert that the pending file still exists.

**Verification pass 2026-10-22 (Phase 22): fixed-verified [static].** Captures stay in pending/ until queued (6f2649e, scan_pipeline.dart processKeeping); test/scan/pending_capture_test.dart passes (flutter test at 495b258: 180 passed, 2 skipped, 0 failed).
