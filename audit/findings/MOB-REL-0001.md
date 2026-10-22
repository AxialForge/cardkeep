---
finding_id: MOB-REL-0001
audit_domain: 11
platform: android
severity: S4
blockers: [data-loss]
title: Restore swap is not crash-safe; a re-run after a partial swap deletes the user's pre-restore data and opens an empty database
status: open
confidence: high
evidence_basis: runtime
affected_component: lib/core/transfer/backup.dart:170-187, lib/main.dart:15-19
affected_screen: App start after choosing Restore
affected_version: 0.6.0 (2010) cdcf49d
---

**Description.** `applyPendingRestore` decides whether to run only by checking that `restore_pending/.ready` exists. That marker is removed last of all (`:185`, `staged.delete`). The steps before it are not idempotent:

1. It deletes `before_restore/` (`:173`).
2. It moves the live DB, WAL and SHM into `before_restore/` (`:175-178`).
3. It moves `cards/` into `before_restore/` (`:180`).
4. It moves the staged DB into place (`:182`).
5. It moves the staged `cards/` into place (`:184`).
6. It deletes `restore_pending/` (`:185`).

If the process dies after step 2 and before step 6 (the OS kills a slow start, the battery dies, or the user force-stops a start that looks frozen while a large `cards/` tree is being renamed), `.ready` is still there on the next start. The re-run then does the following:

- **Killed after step 2, 3 or 4:** step 1 deletes `before_restore/`, which by now holds the user's **only copy of the original database and card images**. If the staged DB was still in `restore_pending`, the restore then completes, but the safety copy is gone for good.
- **Killed after step 4 or 5:** step 1 deletes the original data, and step 2 moves the *restored* DB into `before_restore/`. Step 4 then throws `FileSystemException`, because the staged DB has already been moved. `main()` swallows the error (`debugPrint`, `main.dart:17`). drift finds no `card_organizer.sqlite` and creates an **empty database**. The user sees an empty app. The original data is gone. The restored data sits in a hidden folder that nothing in the UI can reach (MOB-REL-0003). `.ready` is still present, so every later start repeats the failure and **deletes `before_restore/` again**, which destroys the restored data too, while the new empty database is moved aside each time.

The rename steps themselves are fast. What makes the crash window realistic is the directory renames, which run while the app shows no UI before `runApp`, and the fact that a single interruption costs everything with no warning. The consequence is total loss of the contact database, so the severity is S4.

**Preconditions.** The user restored a backup and the app restarts. The process dies partway through `applyPendingRestore`.

**Steps to reproduce (deterministic simulation).**
1. In a temp docs folder, create `card_organizer.sqlite` ("RESTORED"), `before_restore/card_organizer.sqlite` ("ORIGINAL") and `restore_pending/.ready`, with no staged DB. This is the state after a kill following step 4.
2. Call `applyPendingRestore(docs)`.
3. Trace of the code: `before_restore/` with ORIGINAL is deleted at `:173`. RESTORED is moved into `before_restore/` at `:177`. `File(restore_pending/card_organizer.sqlite).rename` throws at `:182`. `docs` has no database, and `.ready` is still present.

**Confirmed by a run (consolidation, 2026-10-21).** A unit test set up the state after a kill following step 4 (live DB = restored copy, `before_restore/` = original, `restore_pending/.ready` present, staged DB already moved) and called `applyPendingRestore(docs)`. Output:

```
error: PathNotFoundException
live db exists: false
before_restore holds: RESTORED
.ready still there: true
```

The original database was deleted, the live database is gone (drift will create an empty one), and the marker remains, so the next start repeats the loss. The test file was removed after the run.

**Expected.** The swap is resumable or transactional. `before_restore` is never deleted while it holds the only copy of user data. A failed swap is rolled back and reported.

**Root cause.** A single completion marker is checked at the start and removed at the end. The delete-first handling of the fallback folder is not idempotent.

**Remediation.**
- Write a journal file (`restore_state`: `moving_old`, `moving_new`, `done`) and resume from the recorded phase.
- Delete the old `before_restore` only after the new swap has finished and the database opens.
- Rename `restore_pending/.ready` to `.applying` before step 1, and if `.applying` is found at start, roll back from `before_restore`.
- Surface failures to the user instead of swallowing them in `main()`.

**Verification.** Unit tests that simulate a kill after each step (set up each intermediate state and call `applyPendingRestore` again) and assert that either the original or the restored database ends up in `docs/` and no copy is lost.

**References.** CWE-367 (TOCTOU-style non-atomic multi-step operation), MASVS-RESILIENCE (data integrity).
