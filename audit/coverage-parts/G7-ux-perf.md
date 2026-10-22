# G7 coverage: GUI (06), UX and accessibility (07), Compatibility (08), Performance (09)

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
