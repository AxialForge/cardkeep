# Appendix B: Inventories (permissions, data, data flow, Data Safety draft)

CardKeep 0.6.0 (2010), commit cdcf49d, Android. Sources: `audit/artifact/manifest-xmltree.txt` (merged release manifest),
`build/app/outputs/logs/manifest-merger-release-report.txt`, `lib/`.

## Permissions

| Permission | Source | Used? where | Runtime request? | Verdict |
|---|---|---|---|---|
| CAMERA | app manifest:2 (also camerax) | Scan screen live camera (`scan_screen.dart:140-160`) | Yes, by camera plugin when Scan opens; denied state handled (`:160-165`) | Keep |
| NFC | app manifest:4 (feature required=false) | Tap screen reader mode (`/tap`) | No (normal) | Keep |
| INTERNET | app manifest:7 | Update check/download (`core/update/updater.dart`); also enables ML Kit telemetry | No | Keep; disclose ML Kit (MOB-PRV-0001) |
| REQUEST_INSTALL_PACKAGES | app manifest:9 | In-app APK update (`updater.dart:201`) | Special access via system settings | Keep for GitHub build only; remove from Play build (MOB-STORE-0001) |
| POST_NOTIFICATIONS | app manifest:11 | Follow-up reminders (`followups/reminders.dart:44-62`) | Yes, Android 13+, when first future follow-up is scheduled | Keep |
| RECEIVE_BOOT_COMPLETED | app manifest:12 (+ flutter_local_notifications) | Re-schedule reminders (non-exported receiver) | No | Keep |
| VIBRATE | flutter_local_notifications | Notification vibration | No | Keep (normal, harmless) |
| ACCESS_NETWORK_STATE | androidx.media3-common (via camerax), datatransport (ML Kit) | Not by app code | No | Harmless normal permission; signals ML Kit telemetry |
| RECORD_AUDIO | camera_android_camerax | No (`enableAudio: false`, `scan_screen.dart:146`) | Never requested | Remove with tools:node="remove" (MOB-BLD-0001, MOB-STORE-0002) |
| READ_MEDIA_IMAGES | open_filex | No (gallery uses Photo Picker, `scan_screen.dart:294`) | Never | Remove; Play Photo/Video policy (MOB-STORE-0002) |
| READ_MEDIA_VIDEO | open_filex | No | Never | Remove (MOB-BLD-0001) |
| READ_MEDIA_AUDIO | open_filex | No | Never | Remove (MOB-BLD-0001) |
| READ_EXTERNAL_STORAGE (max 32) | open_filex | No | Never | Remove (MOB-PRV-0004) |
| WRITE_EXTERNAL_STORAGE (max 28) | camera_android_camerax | No | Never | Remove (MOB-PRV-0004) |
| com.axialforge.cardkeep.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION | androidx.core | Internal signature permission | No | Keep (standard) |

## Data inventory

| Data class | Collected from | Stored | Encrypted | Sent off device | Retention | Deletion |
|---|---|---|---|---|---|---|
| Name, title, company | OCR of card, QR/vCard, NFC, CSV/vCard import, manual | `app_flutter/card_organizer.sqlite` (people, roles, companies) + FTS index | No (MOB-SEC-0005) | Only in user-started share/export/backup; Android auto-backup (MOB-AND-0001) | Indefinite | Tombstone only, never purged (MOB-PRV-0002) |
| Phone, email, address, website | same | contact_points | No | same | Indefinite | Tombstone only |
| Card photos (original q90, rectified q85, thumb) | Camera, gallery | `app_flutter/cards/{original,rectified,thumb}/<sha256>.jpg` | No | Backups (zip includes cards/), share of backup; auto-backup | Indefinite | Deleted with queue card (`card_queue_repository.dart:121-129`); NOT deleted with contact |
| EXIF / GPS of photos | Camera/gallery file | Stripped: re-encoded by OpenCV (`card_detector.dart:168-174`); picker asked without metadata | - | No | Raw camera capture lingers in cache (MOB-SEC-0003) | Cache cleared by OS only |
| Logos cut from cards | Card image | `cards/logo/<sha256>.jpg` | No | Backups | Indefinite | Never deleted (`image_store.dart:66-70`) |
| OCR JSON | ML Kit on device | cards.ocr_json | No | Backups | Indefinite | With card row (tombstone) |
| Notes, tags, events, follow-up dates, career history | User | SQLite | No | Export/backup | Indefinite | Tombstone |
| My card (own details) | User | SQLite | No | User shares it (QR / vCard / SharePlus, `my_card_screen.dart:110`) | Until changed | Edit/clear |
| Pending captures | Camera | `cards/pending/` | No | No (excluded from backups `backup.dart:47`) | Until processed | Deleted on commit (`image_store.dart:53`) |
| Temp OCR/region JPEGs, VACUUM temp | App | system temp | No | No | Seconds | Deleted (`scan_pipeline.dart:200,221`, `backup.dart:44`) |
| Automatic backups | App, weekly | `app_flutter/backups/*.zip` | No | Auto-backup only | Newest 4 kept | Rotated (`backup.dart:150-153`) |
| Manual backups / exports (.zip, .vcf, .csv) | User action | User-chosen SAF location or share target | No | Wherever the user sends them | User-controlled | User-controlled |
| before_restore fallback | Restore | `app_flutter/before_restore/` (db + cards) | No | Auto-backup | Until next restore (indefinite) | No UI (MOB-PRV-0003) |
| Downloaded update APK | GitHub | cache `cardkeep-update.apk` | - | - | Until next update | Deleted/overwritten (`updater.dart:165-188`) |
| Settings (update-on-start etc.) | User | shared prefs | No | Auto-backup | Indefinite | Uninstall |
| SDK diagnostics (ML Kit) | ML Kit | - | TLS | Google (suspected, MOB-PRV-0001) | Google's | n/a |

## Data flow

```
Camera / gallery (Photo Picker) / NFC / QR / .vcf / .csv / .zip
   -> on-device processing (OpenCV EXIF strip, ML Kit OCR + barcode, parsers)
   -> SQLite + cards/ in app-private storage  -> weekly backups/ (keep 4)
   -> user action only: share sheet (vCard, My card, backup) / SAF save (export, backup) -> destination chosen by user
   -> tel:/mailto:/geo:/https links -> user's own apps (on tap)
OS:     Android Backup (allowBackup default) -> user's Google Drive / device transfer   [undisclosed]
Network: Settings > Updates (or opt-in at launch) -> api.github.com -> github.com / objects.githubusercontent.com (APK)
         ML Kit datatransport -> Google logging endpoint (usage/perf stats)               [undisclosed, to confirm]
Notifications: reminder text (name, company, event) on the lock screen                    [MOB-SEC-0002]
```

## Google Play Data Safety draft

Prerequisite: Play build drops REQUEST_INSTALL_PACKAGES and the self-updater (MOB-STORE-0001); privacy policy published (MOB-STORE-0004).

| Question | Draft answer | Justification |
|---|---|---|
| Does the app collect or share any required user data types? | **Yes, collected** if ML Kit telemetry is confirmed (App info and performance > Diagnostics); otherwise **No** | Contact data, photos and notes never leave the device to the developer or a third party; "collected" means transmitted off the device. User-initiated sharing to a destination the user picks is not "sharing" under Play rules. Android Backup is exempt. ML Kit sends SDK usage/performance data to Google (follow Google's ML Kit Data Safety guidance; confirm with capture, MOB-PRV-0001). |
| Data types: Personal info (name, email, phone, address), Photos, Contacts, Other user-generated content | **Not collected** (processed on device only) | `lib/` has no network path for these; update check sends no identifiers. |
| App activity / App info and performance | **Diagnostics: collected by ML Kit (Google)**, not shared, not used for tracking, purpose: analytics/app functionality, cannot be turned off | Pending MOB-PRV-0001; remove the row if the transport is excluded. |
| Device or other IDs | Per ML Kit guidance (likely No) | Verify against Google's ML Kit disclosure. |
| Is all collected data encrypted in transit? | **Yes** | HTTPS (GitHub API; Google transport TLS). |
| Can users request that data be deleted? | **Yes** only after MOB-PRV-0002 is fixed (in-app delete actually purges); data is on-device, uninstall removes it | Today a contact delete is only a tombstone. |
| Data shared with third parties | **None** | No SDKs share data; ML Kit is a service provider processing on the developer's behalf. |
| Independent security review | No | |
| Families / ads | Not designed for children; no ads | |
