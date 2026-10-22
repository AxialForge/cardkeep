---
finding_id: MOB-REL-0004
audit_domain: 20
platform: android
severity: S2
blockers: []
title: An offline or interrupted update download throws an uncaught error and leaves the sheet on its progress bar
status: open
confidence: high
evidence_basis: static
affected_component: lib/core/update/updater.dart:166-176, lib/features/settings/update_sheet.dart:41-57
affected_screen: Settings > Check for updates > Install
affected_version: 0.6.0 (2010) cdcf49d
---

**Description.** `Updater.check` turns every network error into an `UpdateException` (`updater.dart:103-111`), so the update check fails gracefully offline. That part passes domain 20.

`Updater.download` does not do the same. Neither `client.send(req).timeout(20s)` (`:167`) nor the `await for` loop over `resp.stream` (`:172`) is wrapped. A network loss raises a `SocketException`, `ClientException`, `TimeoutException` or `HttpException`. `_install` catches only `on UpdateException` (`update_sheet.dart:50`), so:
- `_progress` stays set and the progress bar stays on screen;
- no error message appears;
- the exception surfaces as unhandled.

A connection that stalls without closing never ends, because the stream has no idle timeout. The partial APK stays in the temp folder until the next attempt deletes it (`:165`).

**Steps to reproduce.**
1. Open the update sheet while online, with an update available.
2. Turn on airplane mode.
3. Tap Install.

**Expected.** "The download did not work. Check your connection." with a way to retry.

**Remediation.**
- Wrap the send and the stream loop in try/catch and rethrow as `UpdateException`.
- Add an idle timeout to the stream (`resp.stream.timeout(...)`).
- In the sheet, also catch generic errors and reset `_progress`.

**Verification.** Unit test with a MockClient that throws mid-stream, asserting an `UpdateException`. Runtime check: airplane mode during a download on the emulator.
