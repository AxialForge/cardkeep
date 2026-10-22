# G6 coverage: store compliance and listing (domains 21 listing, 22, 23)

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
