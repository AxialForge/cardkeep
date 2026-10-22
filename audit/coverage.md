# Coverage & Evidence Matrix

Every control from every domain auditor, merged. States: PASS, PASS-WARN, FAIL, BLOCKED, N/A, NOT TESTED, MANUAL REVIEW. Some auditors used WARN/PARTIAL/NOTE; they count as PASS-WARN (met with a concern) in the totals.


## G1-build-supply


Audited artifact: CardKeep-0.6.0-arm64-v8a.apk (v0.6.0, cdcf49d). Tools: aapt2/apksigner/zipalign 36.0.0. Date 2026-10-21.
Note: the brief listed "21 Dependencies/SBOM"; in domains.md that control set is domain 18 (21 is logging). Covered as 18.

| Domain | Control | State | Basis | Evidence | Finding |
|---|---|---|---|---|---|
| 02 | debuggable off in release | PASS | artifact | manifest-xmltree.txt: no android:debuggable attribute | - |
| 02 | Debug endpoints, test credentials, dev menus, mock services, staging URLs absent | PASS | static | Only outbound host api.github.com (updater.dart:106); no staging host found; Appendix A outbound table | - |
| 02 | Test ad IDs absent | N/A | static | No ads SDK in pubspec.lock | - |
| 02 | Verbose logging off | NOT TESTED | - | Logcat review belongs to logging domain 21 auditor | - |
| 02 | Dev certs removed / no user-CA trust | PASS | artifact | No networkSecurityConfig, no cleartext flag; defaults (no user CA for targetSdk 36) | - |
| 02 | Signing config correct, dev/prod keys separated | PASS-WARN | artifact | apksigner: verifies, 1 signer, cert matches prior releases (Appendix A); debug-key fallback in build.gradle.kts:47 | MOB-BLD-0002 |
| 02 | Signing scheme | PASS-WARN | artifact | v2 true, v3 false | MOB-BLD-0005 |
| 02 | Package ID and versioning correct | PASS | artifact | badging: com.axialforge.cardkeep 0.6.0; pubspec 0.6.0+10; release.yml tag-vs-pubspec check | - |
| 02 | versionCode scheme across ABI splits monotonic | PASS | artifact | arm64 2010 = 2000+10 (Flutter split offsets 1000/2000/4000 x 1 + build); build number increments per release | - |
| 02 | Optimization / minification on | PASS | static | release uses proguard-android-optimize + proguard-rules.pro (Flutter enables R8 for release); ML Kit keep rules present | - |
| 02 | Symbols / mapping archived, not shipped | PASS-WARN | artifact | not shipped (unzip -l); not archived either | MOB-BLD-0004 |
| 02 | No secrets, .env, API keys, private keys in package | PASS | artifact | unzip -l: no .env/.pem/keystore; strings scan for private-key / AIza / ghp_ patterns: no hits | - |
| 02 | No secrets in repo / CI | PASS | static | git ls-files: no jks/keystore/key.properties/.env; .gitignore:55-63 and android/.gitignore:78-80 ignore them; CI uses secrets.* only | - |
| 02 | No unused permissions | FAIL | artifact | RECORD_AUDIO, READ_MEDIA_VIDEO, READ_MEDIA_AUDIO merged in | MOB-BLD-0001 |
| 02 | No unused assets | NOT TESTED | - | Asset-by-asset usage not traced; APK 362 entries, 53.4 MB mostly native libs | - |
| 02 | APK inventory | PASS | artifact | native-libs.txt (libapp, libflutter, libdartcv, ML Kit OCR + barhopper, libsqlite3); zipalign -c -P 16 OK; extractNativeLibs=false | - |
| 02 | Lockfiles committed | PASS | static | pubspec.lock tracked in git | - |
| 02 | Reproducible / provenance-tracked CI build | PASS-WARN | static | Built by release.yml on tag, Flutter pinned 3.47.0; no attestation; byte-for-byte rebuild not attempted | MOB-BLD-0003 |
| 02 | Reproducibility rebuild comparison | NOT TESTED | - | Local OpenCV/NDK rebuild not run in this audit | - |
| 02 | Signing-key protection and backup | MANUAL REVIEW | static | keys/ git-ignored, keystore only in GitHub secrets; offline backup location not documented | MOB-BLD-0005 |
| 02 | Rollback artifact retained | PASS | artifact | Previous APKs remain on GitHub Releases; same key allows reinstall only after uninstall (downgrade blocked by versionCode) | - |
| 03 | Fresh install -> launch -> init | NOT TESTED | - | Runtime install flow owned by functional/runtime auditor on emulator | - |
| 03 | Auth / configure | N/A | - | No accounts (Appendix A) | - |
| 03 | Upgrade previous release -> candidate: DB schema migration | PASS | static | database.dart:32 schemaVersion 3; onUpgrade:47-53 adds table (from<2) and columns (from<3), additive only | - |
| 03 | Upgrade: prefs, caches, user files retained | PASS | static | Same applicationId and signing key; card files in app_flutter/cards untouched by migration | - |
| 03 | Upgrade path via in-app updater integrity | PASS-WARN | static | updater.dart:157-160 https + GitHub host allow-list; :161-163 refuses when neither SHA-256 nor size known; :185-187 SHA-256 check; size-only when digest absent; Android verifies same signer | - |
| 03 | Failed-migration recovery | MANUAL REVIEW | static | No try/rollback around onUpgrade; drift runs it in a transaction; pre-restore copy exists only for restore (CLAUDE.md:121) | - |
| 03 | Encryption migration / credentials retained | N/A | - | No encryption or tokens | - |
| 03 | Upgrade after inactivity, large data, near-full storage | NOT TESTED | - | Runtime only | - |
| 03 | Removal / reinstall: what persists (cloud backup, shared storage) | FAIL | artifact | Auto Backup default on; exports written via SAF/share persist by design | MOB-AND-0001 |
| 03 | Keystore / device IDs / auth state persistence | N/A | - | None used | - |
| 18 | Inventory SDKs, native libs, packages incl. transitive | PASS | static | audit/B-sbom.md from pubspec.lock + native-libs.txt | - |
| 18 | Versions and age (outdated) | PASS-WARN | static | `flutter pub outdated` 2026-10-21: direct go_router 18.1.0->18.1.1, ndef_record 1.4.2 (1.5.0 not resolvable); 21 transitive behind, incl. sqlite3 3.5.2->3.7.1, dartcv4 2.2.2->2.3.1 | - |
| 18 | Known vulnerabilities | MANUAL REVIEW | static | No pub.dev advisory surfaced by pub tooling on 2026-10-21; no external CVE DB lookup (OSV/GHSA) done for bundled native SQLite/OpenCV versions | - |
| 18 | Licences | PASS | static | All BSD/MIT/Apache-2.0 for shipped code; dbus MPL-2.0 is Linux-only (not in APK); ML Kit under Google ML Kit terms; licences shown via Flutter LicensePage expected | - |
| 18 | Maintainer / deprecation / abandonment | PASS-WARN | static | sqlite3_flutter_libs 0.6.0+eol and sqlcipher_flutter_libs 0.7.0+eol are end-of-life stub packages (native lib now via sqlite3 build hooks); remove when drift_flutter allows | - |
| 18 | Ad / analytics / auth / crypto libraries | PASS | static | None besides crypto (SHA-256); firebase-components present only as ML Kit internals, no Firebase services | - |
| 18 | Necessity | PASS | static | Every direct dependency maps to a feature in Appendix A stack | - |
| 18 | SBOM (CycloneDX/SPDX) | PASS-WARN | static | Table SBOM produced (B-sbom.md); no machine-readable SBOM in CI | MOB-BLD-0003 |
| 18 | Lockfile integrity and pinned versions | PASS | static | pubspec.lock committed with sha256 per hosted package; CI runs pub get against it | - |
| 18 | CI supply chain (action pinning) | FAIL | static | Actions pinned by major tag | MOB-BLD-0003 |

Counts: PASS 18, PASS-WARN 8, FAIL 3, MANUAL REVIEW 3, NOT TESTED 5, N/A 4, BLOCKED 0 (total 41).


## G2-local-platform


Runtime checks: the emulator's `dumpsys package` returned "Can't find service: package" during this pass, so runtime-only controls are static and capped at PASS-WARN, or BLOCKED.

| Domain | Control | State | Basis | Evidence | Finding |
|---|---|---|---|---|---|
| 12 | Backup flags (allowBackup / dataExtractionRules / fullBackupContent) | FAIL | artifact | manifest-xmltree.txt:101-106 no attributes | MOB-SEC-0001 |
| 12 | adb backup extraction | PASS-WARN | artifact | targetSdk 36: adb backup excluded on Android 12+; still possible on API 24-30 devices because allowBackup defaults to true | MOB-SEC-0001 |
| 12 | Database at rest (encryption) | WARN | static | drift/SQLite plaintext, app-private; D3 open | MOB-SEC-0005 |
| 12 | Storage location (app-private, no external storage) | PASS-WARN | static | app_flutter/ paths (A architecture); no WRITE_EXTERNAL_STORAGE in manifest; exports via SAF/share only | - |
| 12 | Card images stored as files | PASS-WARN | static | lib/core/images/image_store.dart app_flutter/cards/<sha>.jpg, pending cleanup :53,:68 | - |
| 12 | Temp files: OCR / region jpg | PASS-WARN | static | lib/scan/scan_pipeline.dart:194-221 deleted in finally | - |
| 12 | Temp files: camera capture | FAIL | static | scan_screen.dart:239-255 never deleted | MOB-SEC-0003 |
| 12 | Temp files: VACUUM INTO backup copy | WARN | static | backup.dart:40-44 no finally | MOB-SEC-0003 |
| 12 | Update APK temp | PASS-WARN | static | updater.dart:164-188 deletes on failure/retry | - |
| 12 | Exported backup zip confidentiality | WARN | static | backup.dart:38-50 plaintext zip | MOB-SEC-0005 |
| 12 | Restore zip path traversal (stage) | PASS-WARN | static | backup.dart:121-124 normalize + isWithin, skips escapes; hashes checked in check() | - |
| 12 | Restore safety copy | PASS-WARN | static | backup.dart:170-186 before_restore/ kept | - |
| 12 | Restore zip size / decompression cap | WARN | static | backup.dart:121 decodeBytes of whole zip with no size cap (zip bomb could OOM; user-chosen file, so low); referred to the domain 08/10 auditor | - |
| 12 | Clipboard | WARN | static | contact_detail_screen.dart:418, tap_screen.dart:238 not marked sensitive | MOB-SEC-0007 |
| 12 | Screenshots / recents (FLAG_SECURE) | WARN | static | not set; acceptable until app lock S15.2 | MOB-SEC-0004 |
| 12 | Logs on device (print/debugPrint PII) | PASS-WARN | static | 4 debugPrint of exceptions only; no print() in lib/ | MOB-SEC-0007 |
| 12 | Keyboard cache on sensitive fields | N/A | static | no password/secret fields (no auth) | - |
| 12 | Secrets/keys stored on device | N/A | static | none (no backend, no auth; A scope) | - |
| PLATFORM | Exported components inventory | PASS-WARN | artifact | manifest-xmltree.txt: only MainActivity exported=true plus androidx ProfileInstallerReceiver (exported, permission DUMP, :264-268); all providers/services/other receivers exported=false | - |
| PLATFORM | FileProvider / share providers | PASS-WARN | artifact | providers :166-196 exported=false, grantUriPermissions=true; share via XFile.fromData (contacts_screen.dart:137, contact_detail_screen.dart:66, my_card_screen.dart:113) | - |
| PLATFORM | VIEW/SEND vCard intent handling (readVcf) | WARN | static | MainActivity.kt:47-70 no scheme/authority check; BROWSABLE on VIEW | MOB-SEC-0006 |
| PLATFORM | Incoming payload size cap (1 MB) | PASS-WARN | static | MainActivity.kt:62; vcard_reader.dart:7 maxFilePayload | - |
| PLATFORM | Imports need user confirmation | PASS-WARN | static | A entry points: Import screen confirm (UI verified by the functional auditor) | - |
| PLATFORM | Deep links / App Links | N/A | artifact | flutter_deeplinking_enabled=false; no http(s) intent filter | - |
| PLATFORM | Boot receiver protection | PASS-WARN | artifact | ScheduledNotificationBootReceiver exported=false (AndroidManifest.xml:59) | - |
| PLATFORM | Notification content / lock screen | WARN | static | reminders.dart:65-80 PII, default visibility | MOB-SEC-0002 |
| PLATFORM | Notification payload handling | PASS-WARN | static | payload = person id only (reminders.dart:80), opens /contact/<id> | - |
| PLATFORM | WebView | N/A | static | no webview_flutter / WebView in pubspec or lib | - |
| PLATFORM | URL launching (QR / contact links) | PASS-WARN | static | link_launcher.dart:11 externalApplication only; qr_content.dart:85 non-https warning; opened on tap only | - |
| PLATFORM | Package visibility (<queries>) | PASS-WARN | static | AndroidManifest.xml queries limited to PROCESS_TEXT, VIEW http/https/geo, DIAL, SENDTO mailto/sms | - |
| PLATFORM | Pending intents / implicit internal intents | PASS-WARN | static | MainActivity only starts system NFC/Wireless settings intents | - |
| PLATFORM | Tapjacking / overlay protection | N/A | static | no sensitive confirm actions beyond in-app dialogs; not required at L1 | - |
| 19 | Debuggable flag (release) | PASS-WARN | artifact | manifest-xmltree.txt application has no debuggable attribute (false) | - |
| 19 | Code shrinking / obfuscation | PASS-WARN | artifact | android/app/build.gradle.kts:49 proguard-android-optimize (Flutter release runs R8); classes.dex 4.25 MB; Dart AOT snapshot is not symbolised by --obfuscate (not used; acceptable, no secrets) | - |
| 19 | Root / emulator / hook detection | N/A (accepted) | static | none; local app with no secrets, acceptable at L1 | - |
| 19 | Integrity / anti-tamper (Play Integrity, signature check) | N/A (accepted) | static | none; distribution on GitHub with a stable signing key (A identity) | - |
| 19 | Native libs extracted (extractNativeLibs=false) | PASS | artifact | manifest-xmltree.txt:101 | - |

Counts: 37 controls. PASS 1, PASS-WARN 20, WARN 8, FAIL 2, N/A 6 (2 accepted). BLOCKED none; runtime confirmation of the backup contents (bmgr) and the lock-screen notification is listed for Phase 22.


## G3-network-input


| Domain | Control | State | Basis | Evidence | Finding |
|---|---|---|---|---|---|
| 13 | Cleartext traffic disabled | PASS | artifact | Merged manifest `audit/artifact/manifest-xmltree.txt`: no usesCleartextTraffic, targetSdk 36 (default false) | - |
| 13 | Network security config (no user-CA trust, no debug overrides) | PASS | artifact | No networkSecurityConfig attribute; platform default (system CAs only) | - |
| 13 | All endpoints HTTPS | PASS | static | updater.dart:106 Uri.https; :158 scheme == https | - |
| 13 | Certificate pinning | N/A | static | Public GitHub endpoints, no secrets sent; pinning not warranted | - |
| 13 | No identifiers/PII in requests | PASS | static | updater.dart:107 only Accept + User-Agent headers | - |
| 13 | Timeouts on network calls | PASS | static | updater.dart:109 (12 s), :167 (20 s connect) | MOB-REL-0004 (stream errors) |
| 14 | Update host allow-list | PASS | static | updater.dart:157-159 | - |
| 14 | Update integrity (SHA-256) | PARTIAL | static | updater.dart:149, 161, 185-190 size-only fallback | MOB-API-0001 |
| 14 | Download size limit | FAIL | static | updater.dart:173-177 unbounded | MOB-API-0001 |
| 14 | Redirect handling | PASS | static | package:http follows redirects over TLS to GitHub CDN; initial host checked | - |
| 14 | Downgrade / wrong-signer protection | PASS | static | updater.dart:58 newer-only; Android installer enforces same signer + versionCode | - |
| 14 | Draft/prerelease excluded | PASS | static | updater.dart:122-128 | - |
| 14 | Rate-limit handling | PASS | static | updater.dart:114-116 | - |
| 14 | Install path (REQUEST_INSTALL_PACKAGES / open_filex) | PASS | static | updater.dart:197-206; user confirms in system installer | - |
| 14 | Version comparison robustness | PASS | static | updater.dart:15-35 BigInt parts, pre-release ordering | - |
| CODE | vCard reader size cap | PASS | static | vcard_reader.dart:7,14 (1 MB), field truncation :175 | - |
| CODE | MECARD size cap | PASS | static | vcard_reader.dart:79 (8 KB) | - |
| CODE | CSV import complexity / size cap | FAIL | static+test | csv_import.dart:51,71-74; probe 10k rows 105 s | MOB-SEC-0100 |
| CODE | NFC NDEF parsing / link schemes | PASS | static | ndef.dart:193-197 only http(s)/tel accepted; vCard capped | - |
| CODE | QR classification / link warnings | PASS | static | qr_content.dart:15-32 http(s) only; LinkCheck :82-92 (punycode, IP, shortener, userinfo) | - |
| CODE | Backup zip path traversal | PASS | static | backup.dart:123-124 normalize + isWithin | - |
| CODE | Backup zip bomb / size limit | FAIL | static | backup.dart:81,121 full in-memory decode; transfer_screens.dart:289 | MOB-SEC-0102 |
| CODE | Backup manifest trust / DB validation | PARTIAL | static | backup.dart:100-105 vs 121-127 | MOB-SEC-0102 |
| CODE | Backup newer-schema refusal | PASS | static | backup.dart:94-97 | - |
| CODE | OCR parser ReDoS | PARTIAL | test | rules.dart:55,60,203; 50k chars 84 s | MOB-SEC-0101 |
| PLATFORM | .vcf intent handler size cap | PASS | static | MainActivity.kt:65 (1 MB) | - |
| PLATFORM | .vcf intent URI scheme check | FAIL | static | MainActivity.kt:49-55 | MOB-SEC-0006 (G2) |
| PLATFORM | url_launcher dangerous schemes (javascript:, intent:, file:) | PASS | static+test | link_launcher.dart:45-48 forces https://; tel/sms sanitised :50; external app mode | - |
| PLATFORM | url_launcher malformed input handling | FAIL | test | FormatException outside try | MOB-SEC-0103 |
| PLATFORM | Deep links | N/A | artifact | flutter_deeplinking_enabled=false (Appendix A) | - |
| CODE | SQL injection in raw customSelect/customStatement | PASS | static | contacts_repository.dart:21-40 bound vars; FTS via ftsQuery + `?`; duplicates_repository.dart:295 `$table` from code constants only | - |
| CODE | Notification payload trust | PASS | static | payload = person id routed to /contact/<id> (Appendix A); unknown id shows nothing | - |

Counts: PASS 22, PARTIAL 3, FAIL 5 (one is G2's MOB-SEC-0006), N/A 2. Total 32. No WebSearch used.


## G4-privacy


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


## G5-functional


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


## G6-store


Policies checked 2026-10-21 (sources in C-store-device-open-items.md).

| Domain | Control | State | Basis | Evidence | Finding |
|---|---|---|---|---|---|
| 22 | Apple App Store review guidelines (all) | N/A | static | iOS out of scope (Appendix A) | - |
| 23 | Target API level (36 required for new apps/updates by 2026-08-31) | PASS | artifact | badging.txt targetSdkVersion 36 | - |
| 23 | 16 KB page size: zip alignment | PASS | artifact | zipalign -c -P 16 -v 4: Verification successful on all 3 APKs | - |
| 23 | 16 KB page size: ELF LOAD alignment (arm64) | PASS | artifact | llvm-readelf: all .so LOAD align 0x4000 or 0x10000 | - |
| 23 | AAB format and Play App Signing | FAIL | static | release.yml:49 APK only | MOB-STORE-0003 |
| 23 | REQUEST_INSTALL_PACKAGES / self-update (Device and Network Abuse) | FAIL (Play only) | artifact | manifest line 21; updater.dart | MOB-STORE-0001 |
| 23 | Photo and Video Permissions (READ_MEDIA_IMAGES/VIDEO) | FAIL (Play only) | artifact | manifest lines 90-92 | MOB-STORE-0002 |
| 23 | Microphone (RECORD_AUDIO) unused | FAIL | artifact | manifest line 82 | MOB-STORE-0002 |
| 23 | Camera permission justified by feature | PASS | static | card scanning | - |
| 23 | NFC permission justified | PASS | static | Tap cards (0.6.0) | - |
| 23 | POST_NOTIFICATIONS runtime request | PASS (static) | static | follow-up reminders; runtime prompt owned by permissions domain | - |
| 23 | Exact alarm permission (SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM) | PASS | artifact | not declared; inexact alarms | - |
| 23 | Foreground service types | N/A | artifact | no FOREGROUND_SERVICE permission; services are plugin, non-FGS | - |
| 23 | Privacy policy URL + in-app link | FAIL | static | settings_screen.dart:185 no link | MOB-STORE-0004 |
| 23 | Data safety section | NOT STARTED | static | no Play app | MOB-STORE-0005 |
| 23 | Account deletion | N/A | static | no accounts | - |
| 23 | Families / target audience | N/A (declare 18+/adult business audience) | static | business tool | - |
| 23 | Content rating questionnaire | MANUAL | - | to do in Play Console | - |
| 23 | Package name final | OPEN | static | ROADMAP S0.14 stale | MOB-STORE-0007 |
| 23 | Ads / billing / UGC policies | N/A | static | none present | - |
| 21 | README feature list matches build | FAIL | static | README 0.2.0 vs CHANGELOG 0.6.0 | MOB-STORE-0006 |
| 21 | README privacy claims | PASS | static | consistent with Appendix A network surface | - |
| 21 | GitHub description and topics | PASS | static | gh repo view | - |
| 21 | In-app privacy text ("No account, no cloud, no analytics") | PASS | static | settings_screen.dart:187 | - |
| 23 | GitHub distribution (sideload) readiness | PASS | artifact | signed, same key as prior releases, updater user-started | - |

Counts: PASS 13, FAIL 7, N/A 6, OPEN/NOT STARTED/MANUAL 3 (29 controls).


## G7-ux-perf


Runtime on emulator-5554 (Pixel_10_Pro_XL_test, Android 16 / API 37 image reporting SDK 37, 1344x2992 @ 480 dpi) with the shipped `CardKeep-0.6.0-x86_64.apk`. 3 contacts (2 via vCard import, 1 by hand with very long fields).

| Domain | Control | State | Basis | Evidence | Finding |
|---|---|---|---|---|---|
| 06 | All drawer screens open and render (Contacts, Events, Career moves, Review queue, Follow-ups, Duplicates, Tags, Import, Export and backup, Sync, My card, Settings, Tap cards, Scan, detail, edit) | PASS | runtime | screens/01..30 | - |
| 06 | Placeholder / unfinished features reachable | FAIL | runtime | screens/27_Sync_to_desktop.png | MOB-UX-0002 |
| 06 | Long text overflow (very long name, title, company) at 1.0 / 2.0 font | PASS | runtime | screens/09_detail_long.png, 54_font200_detail.png, 55_font200_contacts.png | - |
| 06 | Dark theme rendering | PASS | runtime | screens/60_dark_contacts.png, 61_dark_detail.png, 62_dark_export.png | - |
| 06 | Landscape rendering / scrolling | PASS (not locked; header scrolls away, list usable) | runtime | screens/40_landscape_contacts.png, 41_landscape_scrolled.png | - |
| 07 | Empty states (Contacts, Events, Notes, Tags, My card, Review) | PASS | runtime | screens/01_launch_empty.png, 20_Events.png, 28_My_card.png | - |
| 07 | Error/unavailable state (no NFC) | PASS | runtime | screens/30_Tap_cards_NFC.png ("No NFC on this phone") | - |
| 07 | Destructive/import confirmation | PASS (Import 2 contacts? Cancel/Import) | runtime | screens/05_import_preview.png | - |
| 07 | Back navigation | FAIL | runtime | back-stack walk output | MOB-UX-0001 |
| 07 | TalkBack labels on icon buttons | PASS (all icon-only controls had content-desc in dumps) | runtime | UI dumps, all screens | - |
| 07 | Text field labels | PASS (visible floating labels/hints; dump EditText text empty is a uiautomator limitation for Flutter hints) | runtime | screens/08_edit_new.png | - |
| 07 | Touch targets >= 48 dp | FAIL | runtime | UI dumps | MOB-A11Y-0001, MOB-A11Y-0002 |
| 07 | Large font 1.3 and 2.0 | PASS (wraps/ellipsizes, no clipping; icons do not scale, acceptable) | runtime | screens/50..55 | - |
| 07 | Contrast | PASS (tokens tested in test/app/theme_test.dart; visual check light+dark; disabled Email exempt) | static+runtime | theme_test.dart, 09/61 screens | - |
| 07 | Permission prompt in context | PASS (camera asked on entering Scan) | runtime | screens/12_scan_perm.png | - |
| 08 | minSdk 24 / target 36 | PASS (static; API 24-35 devices not run) | static | A-scope identity table | - |
| 08 | Orientation lock | PASS (none; configChanges handled) | artifact | manifest-xmltree.txt:110 | - |
| 08 | ABI coverage (arm64, armv7, x86_64 splits) | PASS | artifact | audit/artifact/*.apk | - |
| 08 | Older API levels / real device (S25 Ultra), NFC, real camera | BLOCKED (not available in this run) | - | - | - |
| 09 | Cold start | PASS (742-886 ms warm-cache cold; 1621 ms first after install) | runtime | am start -W | - |
| 09 | APK size per ABI | PASS with note (53.4/41.7/59.6 MB; ML Kit + OpenCV bundled) | artifact | audit/artifact | - |
| 09 | Memory idle / Scan | NOTE | runtime | dumpsys meminfo | MOB-PERF-0001 |
| 09 | Jank / frame timing | BLOCKED (dumpsys gfxinfo sees only 4 frames: Flutter renders through its own surface; profile-mode DevTools needed) | runtime | gfxinfo output | - |
| 09 | Large-library scroll (big5k) | BLOCKED (release build cannot be seeded; no run-as) | - | - | - |

Counts: 24 controls - 17 PASS, 3 FAIL, 1 NOTE, 3 BLOCKED (one BLOCKED row covers older APIs/real device). Findings: 5.
