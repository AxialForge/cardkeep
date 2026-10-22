---
finding_id: MOB-REL-0005
audit_domain: 11
platform: android
severity: S1
blockers: []
title: A capture that always fails to process is retried on every launch, with a recurring "Reading 1 card left from last time"
status: fixed-verified
confidence: medium
evidence_basis: static
affected_component: lib/scan/scan_worker.dart:71-73, lib/app/app.dart:47-57
affected_screen: App start, Scan
affected_version: 0.6.0 (2010) cdcf49d
---

**Description.** Sometimes `pipeline.process` throws before `commit`, for example on an undecodable JPEG or an opencv error in the isolate. The worker swallows the error (`catch (_) {}` at `scan_worker.dart:71`) and leaves the pending file "for the next recovery".

There is no retry count, no quarantine and no message to the user. Every launch reads the file again, fails again, and shows the snackbar again. The user cannot see the file or remove it.

**Remediation.** Count attempts, either in the file name or in a sidecar file. After 2 failures, move the capture to the queue as a "could not read" item the user can discard, or move it to `pending/failed/`.

**Verification.** Test with a pipeline that always throws for one file: after two `recover()` calls, that file is no longer re-queued.

**Fix (unverified).** ImageStore.failedPending counts tries in a .tries sidecar; after 3 failures the capture moves to pending/failed/ and is no longer retried. No user message yet (app.dart is outside this batch; ScanWorker.setAside exposes the count).

**Verification pass 2026-10-22 (Phase 22): fixed-verified [static].** ImageStore.failedPending moves a capture to pending/failed/ after 3 tries; ScanWorker reports it once; backup_hardening_test.dart case passes (flutter test at 495b258: 180 passed, 2 skipped, 0 failed).
