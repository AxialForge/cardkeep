# CardKeep 0.6.0 mobile release audit

| Field | Value |
|---|---|
| Application | CardKeep (com.axialforge.cardkeep) |
| Version / build | 0.6.0, versionCode 2010 (arm64) |
| Commit / tag | cdcf49d / v0.6.0 |
| Platform | Android (iOS out of scope: scaffolding only) |
| Environment | Production (GitHub Releases) |
| Artifact | CardKeep-0.6.0-arm64-v8a.apk, sha256 CC9B63BC…F52501 (+ armeabi-v7a, x86_64) |
| Evidence mode | Artifact + runtime (Android 16 emulator; owner's phone not connected) |
| Identity gate | PASS: the audited APKs are the v0.6.0 release assets; same signing key as earlier releases |
| Audited on | 2026-10-21 |
| Store policies checked | 2026-10-21, Google Play Console Help and Developer Policy Center (Appendix C) |

## DECISION: NO-GO

**Two reachable data-loss defects and two privacy defects are open.** A crash during restore can wipe the whole
contact library (proven by a test), batch-scanned cards can be lost if the app is killed, deleted contacts are
never really deleted, and the app ships Google's ML Kit telemetry library while saying it only goes online for
updates. For Google Play specifically, four more store blockers apply (self-updater, unused media/microphone
permissions, no AAB, no privacy policy). All are fixable; none needs a redesign.

**Coverage:** 194/231 controls tested (PASS 98 + PASS-WARN 55 + FAIL 41), 21 N/A, 8 NOT TESTED, 5 BLOCKED, 3 MANUAL REVIEW.

## Scores (value / coverage of that area)

| Area | Score | Coverage | Basis |
|---|---|---|---|
| Security (local, platform, network, input) | 87/100 | 87% (61/69 tested) | 12 open: 2 S2, 7 S1, 3 S0 |
| Privacy (privacy, permissions, logging) | 82/100 | 89% (34/38) | 4 open: 2 S3, 2 S1 |
| Reliability & data integrity | 61/100 | 91% (32/35) | 9 open: 1 S4, 1 S3, 2 S2, 5 S1 |
| UX, accessibility, performance | 94/100 | 88% (21/24) | 5 open: 1 S2, 3 S1, 1 S0 |
| Store (Google Play) | 75/100 | 69% (20/29) | 7 open: 2 S3, 2 S2, 3 S1 |
| Build & supply chain | 97/100 | 71% (29/41) | 4 open: 3 S1, 1 S0 |

Scores do not override the decision: one S4 data-loss finding alone makes this NO-GO.

**Counts (open):** Blockers 9 · S4 1 · S3 5 · S2 7 · S1 23 · S0 5 · plus 2 duplicates merged.

## Release blockers

| ID | Sev | Class | Defect |
|---|---|---|---|
| MOB-REL-0001 | S4 | data-loss | Restore swap is not crash-safe: a kill mid-swap makes the next start delete the original library and open an empty database (proven by test) |
| MOB-REL-0002 | S3 | data-loss | Batch-scan captures waiting to be read live only in memory; killing the app loses them silently |
| MOB-PRV-0001 | S3 | privacy, store | ML Kit brings Google's datatransport telemetry; contradicts "only goes online for updates / no analytics" (needs a network capture to confirm) |
| MOB-PRV-0002 | S3 | privacy | Deleting a contact keeps its details, card photos and logo forever and copies them into every backup |
| MOB-STORE-0001 | S3 | store (Play only) | In-app APK updater and REQUEST_INSTALL_PACKAGES are not allowed on Play |
| MOB-STORE-0002 | S3 | store | Unused RECORD_AUDIO and READ_MEDIA_IMAGES/VIDEO/AUDIO merged in from camerax/open_filex |
| MOB-STORE-0003 | S2 | store (Play only) | CI builds split APKs only; no AAB, no Play App Signing |
| MOB-STORE-0004 | S2 | store | No privacy policy URL or in-app link |
| MOB-STORE-0005 | S1 | store (Play only) | Data safety answers not prepared (draft in Appendix B) |

For the **current GitHub channel** only the first four rows block a release; the STORE rows block a Play upload.

## High and moderate findings (not blockers)

| ID | Sev | Defect |
|---|---|---|
| MOB-SEC-0001 | S2 | Android auto-backup not declared: contacts DB, photos and backup zips go to Google cloud / device transfer by default |
| MOB-SEC-0100 | S2 | CSV import is quadratic and on the UI thread: 5,000 rows 25 s, 10,000 rows 105 s |
| MOB-REL-0003 | S2 | A failed restore is silent and the `before_restore` safety copy is unreachable from the app |
| MOB-REL-0004 | S2 | Update download that fails offline leaves the progress bar stuck |
| MOB-UX-0001 | S2 | Drawer sections stack: Back walks every section visited before leaving |

The 23 S1 and 5 S0 items are in Appendix A (findings index) and their files.

## What is missing for a GO

1. Fix REL-0001 (journalled, resumable swap; never delete the only copy) and REL-0002 (persist queued captures before reading), with crash-simulation tests.
2. Decide on ML Kit telemetry (MOB-PRV-0001): capture traffic on a device; then disable it if possible or disclose it in the README, app and Data safety.
3. Purge on delete (MOB-PRV-0002): remove rows and image files after an undo window; exclude tombstones from backups.
4. Declare backup rules (MOB-SEC-0001) and say in the app what is and isn't backed up.
5. For Play: a Play flavour without the updater, remove plugin permissions with `tools:node="remove"`, AAB + Play App Signing in CI, a published privacy policy, Data safety answers.
6. Runtime gaps: phone test of NFC and the real camera, the lock-screen notification text, `bmgr` backup contents, a profile-build frame-timing run, and an OSV/GHSA lookup for bundled SQLite and OpenCV.

## Manual review queue

| Item | How to check |
|---|---|
| ML Kit telemetry traffic | Run the release build on a phone behind a proxy (e.g. PCAPdroid) while scanning; look for `firebaselogging-pa.googleapis.com` / `play.googleapis.com/log` |
| Media / microphone prompts | Use every feature on Android 13+; confirm no media or microphone permission dialog ever appears |
| Lock-screen reminder text | Set a reminder 2 minutes ahead, lock the phone, read what shows |
| What Android backs up | `adb shell bmgr backupnow com.axialforge.cardkeep` with a backup transport, then list the backup |
| Keystore backup | Confirm a second copy of `keys/` exists off this PC (losing it means no more updates) |
| Known vulnerabilities | Query OSV for sqlite3 3.50.x and OpenCV 4.x versions bundled by sqlite3/opencv_dart |
| Play content rating, target audience, signing strategy | Owner decisions at Play Console setup |

## Method

Seven domain audits ran in parallel against the same artifact lineage (identity in Appendix A), each writing structured
findings (`audit/findings/`) and a coverage table; the consolidation merged duplicates (MOB-AND-0001 into MOB-SEC-0001,
MOB-BLD-0001 into MOB-STORE-0002) and re-ran the one data-loss proof that an auditor could not finish. No app code was
changed during the audit. Runtime checks used the shipped x86_64 APK on the emulator; phone-only behaviour (NFC, the
real camera, battery saver) is BLOCKED here and listed in the phone test sheets.

Appendices: A scope, identity and attack surface · B inventories (permissions, data, Data safety draft) and SBOM ·
C store checklist and policies · D runtime evidence and screenshots · Findings index · Coverage & Evidence Matrix ·
all findings.
