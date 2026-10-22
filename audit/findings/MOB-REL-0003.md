---
finding_id: MOB-REL-0003
audit_domain: 11
platform: android
severity: S2
blockers: []
title: A failed or bad restore is silent, and the before_restore safety copy cannot be reached from the app
status: fixed (unverified)
confidence: high
evidence_basis: static
affected_component: lib/main.dart:15-19, lib/core/transfer/backup.dart:170-187
affected_screen: Settings > Backup and restore (restart after restore)
affected_version: 0.6.0 (2010) cdcf49d
---

**Description.** `applyPendingRestore` keeps the old database and images in `before_restore/`, but nothing else in `lib/` refers to that folder (`grep -rn before_restore lib` finds only backup.dart). There is no undo for a restore.

If the swap throws, `main()` only logs it with `debugPrint('Restore failed: $e')`. The app then opens whatever is in place, which can be a new, empty database (see MOB-REL-0001), and the user is never told.

A staged database can pass the hash check and still fail to open, for example a backup taken from an already-damaged database. In that case drift fails at open, and nothing rolls back to the old copy automatically.

Each new restore deletes the previous `before_restore` without asking (`backup.dart:173`), so there is only one level of fallback. One level is acceptable. Having no way to reach it is the defect.

**Expected.**
- A failed swap rolls back from `before_restore` and tells the user.
- After a restore, an "Undo restore" option stays available until the next restore.

**Remediation.**
- Wrap the swap in rollback logic, record the outcome in a marker file, and show it in a snackbar on the next start.
- Open the new database once and run `PRAGMA integrity_check` before discarding the old copy.
- Add an "Undo last restore" action that stages `before_restore`.

**Verification.** Test: stage a backup whose database bytes are not SQLite but whose hashes are valid. After apply and open, the old database is back in place and the failure is reported.

**Fix (unverified).** Settings > Backup shows "Data from before the last restore" with Go back to it (staged like a backup, swapped at next start) and Discard; restore outcome snackbar already added in 0.6.1.
