# Appendix C: Store, device and open items

## Policies checked (date + sources)

All fetched 2026-10-21.

| Policy | Current requirement | Source |
|---|---|---|
| Target API level | New apps and updates must target API 36 by 2026-08-31 | https://support.google.com/googleplay/android-developer/answer/11926878 |
| REQUEST_INSTALL_PACKAGES | Only for apps whose core function is package transfer; self-updating outside Play not permitted | https://support.google.com/googleplay/android-developer/answer/12085295 |
| Device and Network Abuse | No updating by means other than Play | https://support.google.com/googleplay/android-developer/answer/9888379 |
| Photo and Video Permissions | READ_MEDIA_IMAGES/VIDEO only for broad-access core use, with declaration; otherwise remove and use Photo Picker; mandatory since 2025-05-28 | https://support.google.com/googleplay/android-developer/answer/14115180 |
| 16 KB page size | Apps targeting 35+ with native code must support 16 KB on 64-bit; updates blocked after 2027-02-01 | https://developer.android.com/guide/practices/page-sizes |
| AAB + Play App Signing | Required for new apps | https://developer.android.com/guide/app-bundle |
| Privacy policy | Required in Console and in app | https://support.google.com/googleplay/android-developer/answer/10144311 |
| Data safety | Required for all apps | https://support.google.com/googleplay/android-developer/answer/10787469 |
| Metadata | Listing must be accurate | https://support.google.com/googleplay/android-developer/answer/9898842 |

## Play submission checklist

| Item | Status | Action |
|---|---|---|
| targetSdk 36 | Done | - |
| 16 KB alignment (zip + ELF) | Done | Recheck after dependency upgrades |
| AAB + Play App Signing | Missing | MOB-STORE-0003 |
| Play flavour without updater / REQUEST_INSTALL_PACKAGES | Missing | MOB-STORE-0001 (S17.9) |
| Remove RECORD_AUDIO, READ_MEDIA_* | Missing | MOB-STORE-0002 |
| Privacy policy + in-app link | Missing | MOB-STORE-0004 (S17.6, S15.11) |
| Data safety form | Not started | MOB-STORE-0005 |
| Package name decision recorded | Open | MOB-STORE-0007 |
| Content rating questionnaire | Not started | Fill in Console (expected Everyone) |
| Target audience | Not started | Declare adults; not a Families app |
| Store listing text and screenshots | Not started | Write from updated README (MOB-STORE-0006) |
| Closed test (12 testers, 14 days for new personal accounts) | Not started | ROADMAP D7; verify current tester rule at submission |
| Account deletion | N/A | No accounts |

GitHub distribution: fine as is (updater is user-started, signed with the same key).

## Listing accuracy

| Claim | Where | True? |
|---|---|---|
| No account, no cloud, keep everything local | Repo description, README, Settings | Yes |
| Cards read on the phone, nothing uploaded | README | Yes (bundled ML Kit models) |
| Only goes online for update checks; startup check off by default | README Privacy | Yes per Appendix A |
| "What it does (0.2.0)" | README | No, app is 0.6.0 (MOB-STORE-0006) |
| Light, Medium and Dark themes | README | No, Medium removed in 0.6.0 |
| NFC, import/export, tags, events, career tracking are "next" | README | No, shipped |
| Topics ml-kit, ocr, opencv, offline-first, privacy | GitHub topics | Yes |

## Device matrix

Store-related device checks needed: Play build on a 16 KB page-size emulator image (Android 15+ 16 KB system image) to confirm the app launches and scans; Photo Picker import on API 33+ and API 29 after MOB-STORE-0002.

## Manual review queue

- Confirm ML Kit bundled text/barcode models send no telemetry (affects Data safety).
- Decide signing key strategy for Play App Signing (shared with GitHub key or not).
- Confirm at runtime whether any READ_MEDIA_* or RECORD_AUDIO prompt ever appears (MOB-STORE-0002 confidence medium).
- Content rating questionnaire and target audience answers.
