# Appendix A: Scope, method, identity and attack surface

## Scope (Phase 0)

| Item | Decision | Evidence |
|---|---|---|
| Platform | **Android only** | `android/` configured (applicationId, release signing, CI release job). `ios/` is unmodified Flutter scaffolding; iOS is "later" in `docs/ROADMAP.md` (S14.4). iOS: out of scope. |
| Backend/API (domains 13, 14) | **N/A** except the update check | No server of our own. Only outbound call is the user-started (or opt-in at launch) GitHub Releases check and APK download (`lib/core/update/updater.dart`). Treated as a network surface in domain 13. |
| Accounts / authentication (15) | **N/A** | No sign-up or sign-in anywhere; code search finds no auth SDK. App lock is planned (S15.2) and not yet built. |
| Payments / billing | **N/A** | No billing dependency in `pubspec.yaml` or Gradle. |
| Ads / analytics / crash reporting | **N/A** (verified) | No ads, analytics, Firebase or crash SDK in `pubspec.lock` (checked in domain 21). |
| User-generated content shared with others | **N/A** | Single-user, on-device. |
| Threat model | Personal contact data (names, phones, emails, addresses, card photos, notes) on one phone. Main risks: data loss, other apps or backups reading it, a malicious file/tag/QR/update, over-broad permissions, store-policy rejection. Physical attacker with an unlocked phone is out of scope (no app lock yet; S15.2). |

## Evidence mode

**Artifact + runtime.** The audited artifacts are the APKs CI attached to GitHub Release v0.6.0, plus runtime checks on the
Android emulator (Pixel_10_Pro_XL_test, Android 16 x86_64) with the same release's x86_64 APK. The owner's phone
(Galaxy S25 Ultra) is not connected for this audit; phone-only behaviour (NFC, real camera) is BLOCKED and listed for
the phone test sheets.

## Identity (Phase 1, domain 01)

| Field | Value |
|---|---|
| App name | CardKeep |
| Package | com.axialforge.cardkeep |
| Version | 0.6.0, versionCode 2010 (arm64 split: 2000 + 10) |
| Commit / tag | cdcf49d38afbb9ed672840c442cdd2dfc76b0db0 / v0.6.0 (clean tree) |
| minSdk / targetSdk / compileSdk | 24 / 36 / 37 |
| Signing | Signer DN `CN=AxialForge, O=AxialForge, C=US`, cert SHA-256 `4ffa7fe0…3a2820`; same key as earlier releases (in-place updates work) |
| Distribution | GitHub Releases (public repo AxialForge/cardkeep); Google Play not yet (M9) |
| Artifacts (SHA-256) | arm64-v8a `CC9B63BC…F52501` (53.4 MB); armeabi-v7a `A2446A3F…8E564` (41.7 MB); x86_64 `B94EFE3C…AA9EF7` (59.6 MB) |
| Stack | Flutter 3.47 / Dart 3.13, drift (SQLite + FTS5), Riverpod, go_router, camera, opencv_dart, ML Kit text + barcode (bundled models), nfc_manager, flutter_local_notifications, file_picker, archive, share_plus, url_launcher, qr_flutter |
| Data classes | Contact identity and contact details (name, title, company, phone, email, address, website), card photos, notes, tags, events, follow-up dates, own card (My card) |

**Identity gate: PASS.** Audited APKs are exactly the release assets for tag v0.6.0 at commit cdcf49d; signing
certificate matches previous releases.

## Architecture (Phase 2)

```
Camera / gallery / NFC / .vcf / .csv / .zip  ->  Flutter UI  ->  parsers (OCR, QR, vCard, CSV, NDEF)
   -> repositories (drift)  ->  SQLite file  app_flutter/card_organizer.sqlite   (app-private)
                             ->  card images  app_flutter/cards/{original,rectified,thumb,logo}/<sha256>.jpg
   -> exports/backups -> share sheet or Storage Access Framework (user picks destination)
Network: only Settings > Updates -> api.github.com (release list) -> github.com/objects.githubusercontent.com (APK)
```

### Entry points

| Entry point | Where | Notes |
|---|---|---|
| Launcher activity | MainActivity (exported, MAIN/LAUNCHER) | |
| VIEW `text/x-vcard`, `text/vcard`, `text/directory` (content scheme) | MainActivity intent filter | File read by `MainActivity.readVcf`, capped 1 MB, handed to Import (user confirms) |
| SEND `text/x-vcard`, `text/vcard` | MainActivity intent filter | Same path |
| Notification tap | flutter_local_notifications | payload = person id; opens `/contact/<id>` |
| Boot completed / package replaced | ScheduledNotificationBootReceiver (exported=false) | Re-schedules reminders |
| NFC reader mode | Tap screen only, foreground | No NFC intent filter in the manifest (tags are not delivered when the app is closed) |
| File imports | file_picker (SAF) | .vcf / .csv / .zip chosen by the user |
| Gallery photos | image_picker | Card photos |
| QR codes on cards | ML Kit barcode | Links shown with domain + warnings, opened only on tap |
| Deep links | **disabled** (`flutter_deeplinking_enabled=false`) | |

### Outbound hosts

| Host | When | Data sent |
|---|---|---|
| api.github.com | Update check (Settings, or at launch when the user turned it on) | Standard HTTP request, no identifiers |
| github.com / objects.githubusercontent.com | Update download (user confirms) | none |
| Any URL / tel: / mailto: / geo: | Only when the user taps it | Opened in the user's own apps via url_launcher |

Store policies were checked during the audit (domain 23); the date and sources are recorded in Appendix C.
