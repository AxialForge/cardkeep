# G5: Functional, reliability, data integrity, offline (domains 04, 11, 20)

Auditor G5. Release 0.6.0 (2010), commit cdcf49d. These domains are numbered as in `references/domains.md`: 04 is functional completeness, 11 is reliability and failure (which includes data integrity here), 20 is offline. The brief's "05 functional correctness" and "10 reliability" labels are mapped onto 04 and 11.

## Automated results

| Check | Result |
|---|---|
| `flutter test` (full suite, run 2026-10-21) | **162 passed, 2 skipped, 0 failed** ("All tests passed!") |
| `flutter analyze` | 14 issues, all `info` level. Some come from the temporary `test/audit_tmp/` probe files, which were deleted afterwards. No errors or warnings were reported. |

## Coverage

| Domain | Control | State | Basis | Evidence | Finding |
|---|---|---|---|---|---|
| 04 | Feature inventory built from roadmap, changelog, router and drawer | PASS | static | Inventory below; `lib/app/router.dart:40-104`, `lib/app/drawer.dart:18-38` | - |
| 04 | Unit/widget tests for the core features | PASS | static+test | 162 passed, 2 skipped | - |
| 04 | Unbuilt features are labelled, not broken | PASS | static | `/sync` is shown as ComingSoon (milestone 0.8), `router.dart:100-104` | - |
| 04 | Interrupted and cancelled paths: batch scan | FAIL | static | `scan_worker.dart:36-41`, `scan_pipeline.dart:122-134` | MOB-REL-0002 |
| 04 | Retry path: update download | FAIL | static | `update_sheet.dart:41-57` | MOB-REL-0004 |
| 04 | Duplicate path: same photo imported twice, then discard | FAIL | static | `card_queue_repository.dart:120-131` | MOB-REL-0008 |
| 04 | Every interactive control exercised at runtime | NOT TESTED | - | Runtime pass is owned by the UX/runtime auditor; widget flow `test/features/contacts_flow_test.dart` only | - |
| 11 | Schema migration v1 to v2 to v3 is correct | PASS | static | `database.dart:47-55`; added columns are defaulted or nullable (`tables.dart:43-45, 83`) | - |
| 11 | Migration is covered by a test | FAIL | static | No migration test, no schema dumps | MOB-REL-0009 |
| 11 | Restore: backup verified before staging (hashes, newer schema, zip-slip) | PASS | static+test | `backup.dart:81-121, 129-133`; `test/transfer/transfer_test.dart:193-201` | - |
| 11 | Restore swap survives being killed partway | FAIL | static+test | `backup.dart:170-187` | MOB-REL-0001 |
| 11 | Restore failure is reported and rolled back; fallback reachable | FAIL | static | `main.dart:15-19`; no UI references `before_restore` | MOB-REL-0003 |
| 11 | Second restore overwrites before_restore | PARTIAL | static | `backup.dart:173`; by design only one level of fallback (covered under MOB-REL-0003) | MOB-REL-0003 |
| 11 | Merge and undo are atomic | PASS | static+test | `duplicates_repository.dart:117, 252` use `db.transaction`; `test/dupes/merge_test.dart` | - |
| 11 | Retire / moveFollowup are atomic | PASS | static | `career_repository.dart:243, 341, 410` | - |
| 11 | Career changeJob is atomic | FAIL | static | `career_repository.dart:266-330` has no transaction | MOB-REL-0006 |
| 11 | Import merge is atomic and idempotent | PARTIAL | static | `transfer_repository.dart:157-196`; re-running is safe thanks to matching, but there is no transaction | MOB-REL-0006 |
| 11 | Tag delete is atomic | PASS | static | `tags_repository.dart:104` | - |
| 11 | Event delete is atomic and keeps links | PARTIAL | static | `events_repository.dart:116-122` keeps the people links but uses two statements | MOB-REL-0006 |
| 11 | Contact delete is a tombstone with undo | PASS | static+test | `contacts_repository.dart:343-349`; flow test "delete from detail with undo" | - |
| 11 | Scan-queue crash recovery | FAIL | static | `scan_worker.dart:44-50` sees only `pending/`; queued jobs are held in RAM | MOB-REL-0002 |
| 11 | A capture that keeps failing is handled | FAIL | static | `scan_worker.dart:71-73` | MOB-REL-0005 |
| 11 | Image store: no shared-file deletion | FAIL | static | `image_store.dart:66-70` | MOB-REL-0008 |
| 11 | Follow-up rescheduling | PASS | static+test | `followups_repository.dart:76`; `test/followups/followups_repository_test.dart` | - |
| 11 | Reminder ids and cancelAll side effects | PARTIAL | static | `reminders.dart:52, 62` | MOB-REL-0007 |
| 11 | Silent `catch (_) {}` sites | PARTIAL | static | `app.dart:70, 108, 117, 127` are startup niceties (acceptable). `card_queue_repository.dart:98` (logo) is acceptable. `scan_worker.dart:71` hides failures (MOB-REL-0005). `main.dart:17` hides a restore failure (MOB-REL-0003) | MOB-REL-0003, MOB-REL-0005 |
| 11 | Unawaited futures | PASS | static | Only navigation pushes, haptics and the `ScanWorker._run` loop, which catches its own errors (`scan_worker.dart:40, 53-82`) | - |
| 11 | Auto backup rotation | PASS | static | `backup.dart:136-157`; keeps 4; excludes `cards/pending` | - |
| 11 | Fault injection at runtime (low storage, revoked permission, reboot) | NOT TESTED | - | Emulator runtime is owned by another group; phone-only items are BLOCKED | - |
| 20 | App works fully offline (no network needed outside update) | PASS | static | The only HTTP client is `lib/core/update/updater.dart` (see Appendix A) | - |
| 20 | Update check offline fails gracefully | PASS | static+test | `updater.dart:103-117` maps errors to `UpdateException`; startup is silent (`app.dart:93`); `test/update/updater_test.dart` | - |
| 20 | Update download offline or interrupted | FAIL | static | `updater.dart:166-176` | MOB-REL-0004 |
| 20 | Network change mid-download / stall timeout | FAIL | static | No idle timeout on the stream | MOB-REL-0004 |
| 20 | Airplane-mode runtime check | NOT TESTED | - | Runtime group | - |

Counts: 35 controls. PASS 15, FAIL 12, PARTIAL 5, NOT TESTED 3.

## Feature inventory

| Feature | Where (entry point) | Tests | Verified how |
|---|---|---|---|
| Contacts list, search (FTS5), detail, edit, delete with undo | `/`, `/contact/:id`, `/contact/:id/edit`; `contacts_repository.dart` | yes (`contacts/`, `features/contacts_flow_test.dart`) | test + static |
| New contact (manual or from scan) | `/contact/new` | yes | test |
| Card scan (camera, single/pile, gallery import, manual crop) | `/scan`, `/scan/crop`; `scan_pipeline.dart`, `scan_worker.dart` | partial (`scan/` detector, geometry, ML Kit fixture; no worker test) | static (MOB-REL-0002, -0005) |
| Card parser (OCR to fields, v3 fields) | `lib/scan`, parser | yes (`parser/`, `core/fields_v3_test.dart`) | test |
| Review queue, auto-save of clean cards | `/queue`; `card_queue_repository.dart` | yes (`cards_queue/`) | test + static (MOB-REL-0008) |
| NFC tap (NDEF read/write, My card) | `/tap`, `/mycard` | yes (`nfc/ndef_test.dart`) | test; hardware BLOCKED (phone) |
| Duplicates detect, merge, undo, not-a-duplicate | `/duplicates`, `/merge/:a/:b` | yes (`dupes/`) | test + static |
| Career moves (suggestions, change job, retire, succession) | `/career`; `career_repository.dart` | yes (`career/`) | test + static (MOB-REL-0006) |
| Events and scan sessions (auto-start, met-at) | `/events`, `/event/:id` | yes (`events/`) | test + static |
| Follow-ups and reminders | `/followups`; `reminders.dart` | repository yes; reminders plugin no | test + static (MOB-REL-0007) |
| Tags (system and user, bulk) | `/tags` | yes (`tags/`) | test |
| Import vCard / CSV with saved mapping, share-to-import | `/import`, `/import/csv`, intent channel | yes (`vcard/`, `transfer/`) | test + static |
| Export (vCard/CSV) and backup/restore, weekly auto backup | `/export`; `backup.dart` | yes (`transfer/transfer_test.dart`) | test + static (MOB-REL-0001, -0003) |
| In-app update (GitHub Releases) | Settings > update sheet; `updater.dart` | yes, check path (`update/`) | test + static (MOB-REL-0004) |
| Settings (theme, auto save, auto backup, update on start, search engine) | `/settings` | partial (flow test, web search engine) | test |
| OCR debug capture | `/debug/ocr` | no | static (route is registered in release builds) |
| Sync to desktop | `/sync` (ComingSoon, 0.8) | n/a | static: placeholder |
