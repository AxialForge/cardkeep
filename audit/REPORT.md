# CardKeep 0.6.1 mobile release audit

| Field | Value |
|---|---|
| Application | CardKeep (com.axialforge.cardkeep) |
| Version / build | 0.6.1, versionCode 4011 (x86_64 split; pubspec 0.6.1+11) |
| Commit / tag | 495b258 (main HEAD, untagged) on top of v0.6.1 = 60385c9 |
| Platform | Android (iOS out of scope: scaffolding only) |
| Environment | Production candidate (GitHub Releases); Google Play planned |
| Artifact | build/app/outputs/flutter-apk/app-x86_64-release.apk built from 495b258, sha256 9ff12000…295b676d, signer 4ffa7fe0…3a2820 (release key) |
| Evidence mode | Artifact + runtime (Android 16 emulator) + static; original audit on the 0.6.0 release assets |
| Identity gate | PASS-WARN: verified APK is a local build of 495b258 with the release key; the v0.6.1 tag (60385c9) predates 33 of the fixes, so the build to publish must be tagged from 495b258 or later |
| Audited on | 2026-10-21 (full), 2026-10-22 (Phase 22 verification) |
| Store policies checked | 2026-10-21, Google Play Console Help and Developer Policy Center (Appendix C) |

## DECISION

| Channel | Decision | Reason |
|---|---|---|
| **GitHub Releases (sideload)** | **CONDITIONAL GO** | Every data-loss, privacy and security finding is fixed and verified; no open S4/S3 or blocker applies to this channel. Conditions below. |
| **Google Play** | **NO-GO** | Four store blockers remain open: MOB-STORE-0001 (self-updater + REQUEST_INSTALL_PACKAGES), MOB-STORE-0003 (no AAB / Play App Signing), MOB-STORE-0004 (no privacy policy), MOB-STORE-0005 (Data safety answers). |

**Conditions for the GitHub GO.**
1. Publish from a tag at 495b258 or later (e.g. v0.6.2) through release.yml, so the shipped APKs match the verified lineage; confirm the run attaches the symbols zip, mapping and SHA256SUMS.txt (MOB-BLD-0004) and fails without key.properties (MOB-BLD-0002).
2. Clear the manual review queue items for the GitHub channel: off-PC keystore backup, OSV lookup for bundled SQLite/OpenCV, lock-screen reminder text on a device.

**Coverage (Phase 22 recount of coverage.md):** 166/200 controls tested (PASS 130 + PASS-WARN 32 + FAIL 4), 16 N/A, 9 NOT TESTED, 5 BLOCKED, 4 MANUAL REVIEW.

## Scores (value / coverage of that area)

| Area | Score | Coverage | Basis (open findings) |
|---|---|---|---|
| Security (local, platform, network, input) | 100/100 | 87% (61/69) | 1 open S0 (SEC-0005) |
| Privacy (privacy, permissions, logging) | 100/100 | 89% (34/38) | none open |
| Reliability & data integrity | 100/100 | 91% (32/35) | none open; fixes mostly [static] + tests |
| UX, accessibility, performance | 100/100 | 88% (21/24) | 1 open S0 (PERF-0001); a11y fixes not re-measured |
| Store (Google Play) | 85/100 | 69% (20/29) | 4 open: 1 S3, 2 S2, 1 S1 |
| Build & supply chain | 100/100 | 71% (29/41) | 1 open S0 (BLD-0003 partial) |

Many fixes are verified [static] with passing tests rather than on a device; the scores mean "no known open defect", not "proven on hardware". The Play NO-GO overrides the store number.

**Counts.** Open 7: Blockers 4 (store, Play only) · S4 0 · S3 1 · S2 2 · S1 1 · S0 3. Fixed-verified 34 (12 [artifact]-backed or with runtime support, 22 [static] with tests/code). Reopened 0. Duplicates 2.

## Release blockers (Play channel only)

| ID | Sev | Class | Defect |
|---|---|---|---|
| MOB-STORE-0001 | S3 | store | In-app APK updater and REQUEST_INSTALL_PACKAGES are not allowed on Play (still in the HEAD APK) |
| MOB-STORE-0003 | S2 | store | CI builds split APKs only; no AAB, no Play App Signing |
| MOB-STORE-0004 | S2 | store | No privacy policy URL or in-app link |
| MOB-STORE-0005 | S1 | store | Data safety answers not prepared (draft in Appendix B) |

No blocker applies to the GitHub channel.

## Other open findings

| ID | Sev | Defect |
|---|---|---|
| MOB-BLD-0003 | S0 (was S1) | Actions now SHA-pinned and SHA256SUMS published; still no provenance attestation or SBOM |
| MOB-PERF-0001 | S0 | About 80 MB stays allocated after leaving Scan |
| MOB-SEC-0005 | S0 | Database, card images and backup zips unencrypted (decision D3; owner choice) |

## Verification pass 2026-10-22

Phase 22 re-tested every finding fixed in 17cad64, 6f2649e, 3235577, 60385c9 (v0.6.1) and 495b258 against HEAD 495b258.

- **Tests:** `flutter test` at 495b258: 180 passed, 2 skipped (seed tool), 0 failed. New tests cover crash-at-every-step restore (REL-0001), kept captures (REL-0002), purge and backup exclusion (PRV-0002), backup hardening and fallback copy (SEC-0102, REL-0003, PRV-0003, REL-0005), schema upgrade v1 to v3 (REL-0009), hostile CSV/OCR/URL input (SEC-0100, -0101, -0103), stable reminder ids (REL-0007), missing digest and offline update (API-0001, REL-0004).
- **Artifact (aapt2/apksigner on app-x86_64-release.apk):** permissions are CAMERA, NFC, INTERNET, REQUEST_INSTALL_PACKAGES, POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED, VIBRATE, ACCESS_NETWORK_STATE and the dynamic-receiver permission: no RECORD_AUDIO, READ_MEDIA_*, or READ/WRITE_EXTERNAL_STORAGE (STORE-0002, PRV-0004). allowBackup=false with fullBackupContent and dataExtractionRules (SEC-0001). The datatransport TransportBackendDiscovery service has no CctBackendFactory meta-data (PRV-0001). v2 + v3 signing, release-key signer (BLD-0005).
- **Runtime (emulator, HEAD release build):** app launches; camera permission, system gallery picker and OCR of a test card work with no logcat errors (supports PRV-0001 and STORE-0002).
- **Result:** 34 fixed-verified, 1 partial kept open and downgraded (BLD-0003), 0 reopened.
- **Not re-run:** network capture for ML Kit (classes still ship, backend unregistered), uiautomator re-measure of the 48 dp targets, lock-screen/recents checks, `am start file://` probe, API 28 update install, a tagged CI run of the new release workflow. These fixes are fixed-verified [static] and the coverage rows for runtime behaviour stay PASS-WARN.

## What is missing for a Play GO

1. A Play flavour without the updater and with REQUEST_INSTALL_PACKAGES removed (STORE-0001).
2. AAB build plus Play App Signing decision (STORE-0003).
3. A published privacy policy linked from Settings (STORE-0004), and Data safety answers from the final AAB (STORE-0005), stating that ML Kit runs on-device.
4. Runtime gaps: phone test of NFC and the real camera, a network capture of the Play build, a profile-build frame-timing run.

## Manual review queue

| Item | How to check |
|---|---|
| ML Kit traffic (confirmation only) | Proxy capture (e.g. PCAPdroid) while scanning on the HEAD build; expect no firebaselogging-pa / play.googleapis.com/log requests |
| Lock-screen reminder text | Set a reminder 2 minutes ahead, lock the phone: only "CardKeep" should show |
| Keystore backup | Confirm a second copy of `keys/` exists off this PC (docs/RELEASE-SIGNING.md) |
| Known vulnerabilities | Query OSV for the sqlite3 and OpenCV versions bundled by sqlite3/opencv_dart |
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
