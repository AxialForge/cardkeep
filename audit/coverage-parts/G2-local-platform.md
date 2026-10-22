# Coverage part G2: local data security (12), MASVS-PLATFORM, tamper/resilience (19)

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
