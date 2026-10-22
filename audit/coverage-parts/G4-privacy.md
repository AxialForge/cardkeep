# G4 coverage: Privacy (16), Permissions (17), Logging/telemetry (18 in this audit = domains.md 21)

| Domain | Control | State | Basis | Evidence | Finding |
|---|---|---|---|---|---|
| 16 | Data-flow inventory built (every data class) | Pass | static | audit/B-inventories.md | - |
| 16 | No account; account deletion requirement | N/A | static | A-scope: no auth | - |
| 16 | No ads / analytics / crash SDK | Partial | artifact | pubspec.lock clean; ML Kit datatransport present | MOB-PRV-0001 |
| 16 | Declared vs actual network use (README, Settings) | Fail | artifact | README.md:50-53; settings_screen.dart:161,186 | MOB-PRV-0001 |
| 16 | Card photos stored without EXIF | Pass | static | card_detector.dart:168-174; image_store.dart:7-9; pickMultiImage(requestFullMetadata:false) scan_screen.dart:294 | - |
| 16 | Temp/capture files removed | Fail | static | scan_screen.dart:252-253; scan_pipeline.dart:200,221 delete OCR temps; backup.dart:44 deletes VACUUM temp | MOB-SEC-0003 |
| 16 | Contact delete removes personal data | Fail | static | contacts_repository.dart:343-346; database.dart:61-67 | MOB-PRV-0002 |
| 16 | Card images deleted with card (queue) | Partial | static | card_queue_repository.dart:121-129 (images yes, logo no) | MOB-PRV-0002 |
| 16 | Backups exclude deleted data | Fail | static | backup.dart:42 VACUUM INTO | MOB-PRV-0002 |
| 16 | Exports exclude deleted data | Pass | static | transfer_repository.dart:82 | - |
| 16 | Auto backups bounded retention | Pass | static | backup.dart:136-155 keep=4 | - |
| 16 | before_restore fallback retention | Fail | static | backup.dart:168-186 | MOB-PRV-0003 |
| 16 | OS cloud backup scope declared | Fail | artifact | manifest-xmltree.txt line=101 no allowBackup | MOB-AND-0001, MOB-SEC-0001 |
| 16 | Data at rest encryption | Partial | static | unencrypted SQLite (decision open) | MOB-SEC-0005 |
| 16 | Data leaves device only on user action (share/export/SAF) | Pass | static | SharePlus calls contacts_screen.dart:134, contact_detail_screen.dart:63, my_card_screen.dart:110, transfer_screens.dart:52 | - |
| 16 | Update check sends no identifiers, off by default | Pass | static | settings_screen.dart:155-163; A-scope outbound table | - |
| 16 | Lock-screen notification content | Fail | static | reminders.dart:65-79 | MOB-SEC-0002 |
| 16 | Recents/screenshot exposure | Partial | static | no FLAG_SECURE | MOB-SEC-0004 |
| 16 | Privacy policy exists and linked | Fail | static | ROADMAP.md:546, :496 | MOB-STORE-0004 |
| 16 | Data Safety answers prepared | Partial | static | draft in B-inventories.md | MOB-STORE-0005, MOB-PRV-0001 |
| 16 | Debug OCR capture screen (writes to external app dir) unreachable in release | Pass | static | drawer.dart:147 kDebugMode; deep links disabled | - |
| 17 | Merged manifest permission inventory | Pass | artifact | B-inventories.md Permissions | - |
| 17 | Minimum necessary permissions | Fail | artifact | manifest-xmltree.txt lines 82-92 | MOB-BLD-0001, MOB-STORE-0002, MOB-PRV-0004 |
| 17 | REQUEST_INSTALL_PACKAGES justified for channel | Partial | artifact | ok for GitHub build; not allowed on Play | MOB-STORE-0001 |
| 17 | Camera requested in context (on opening Scan) | Pass | static | camera plugin request at controller init, scan_screen.dart:140-160 | - |
| 17 | Camera denial handled (denied state, gallery still works) | Pass | static | scan_screen.dart:160-165 | - |
| 17 | Camera allow / deny / don't-ask-again at runtime | Blocked | - | emulator runtime run belongs to G-runtime; phone camera not connected | - |
| 17 | Notification permission requested in context (first future follow-up) | Pass | static | reminders.dart:58-62 | - |
| 17 | Notification denial degrades gracefully | Pass | static | requestPermission result ignored; app works without reminders | - |
| 17 | In-app rationale before notification prompt | Partial | static | none shown; system prompt is contextual enough | - |
| 17 | NFC not required, foreground reader mode only | Pass | artifact | AndroidManifest.xml:4-5 required=false; no NFC intent filter | - |
| 17 | Camera feature not required | Pass | static | AndroidManifest.xml:14 | - |
| 17 | RECEIVE_BOOT_COMPLETED receiver not exported | Pass | artifact | A-scope entry points | - |
| 17 | Location / contacts / phone permissions | N/A | artifact | not requested | - |
| 18 | No PII in release logs | Partial | static | debugPrint scan_screen.dart:260, main.dart:18, scan_pipeline.dart:159,180; no print() | MOB-SEC-0007 |
| 18 | Telemetry matches declarations | Fail | artifact | datatransport in merged manifest | MOB-PRV-0001 |
| 18 | Crash/error reporting (supportability) | Partial | static | none by design; user-visible error messages only; symbols not archived | MOB-BLD-0004 |
| 18 | Logcat check at runtime | Blocked | - | not run in this part; needs emulator logcat during failed scan | - |

Totals (38 controls): Pass 15, Partial 9, Fail 10, N/A 2, Blocked 2. Domain 18 here maps to domains.md section 21 (Logging, telemetry, supportability).
