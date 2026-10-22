# Appendix D: Runtime evidence (GUI, UX, accessibility, compatibility, performance)

Device: emulator-5554, Pixel_10_Pro_XL_test, Android 16 x86_64 image (`getprop ro.build.version.sdk` = 37), 1344x2992, 480 dpi (3.0x).
Build: shipped `audit/artifact/CardKeep-0.6.0-x86_64.apk`, installed after uninstalling any previous `com.axialforge.cardkeep`.
Data: 2 contacts imported from `/sdcard/Download/test_import.vcf`, 1 added by hand with long fields. Font scale and night mode were reset to 1.0 / off at the end.

## Measurements

| Metric | Value | How measured |
|---|---|---|
| Cold start, run 1 (first after install) | 1621 ms TotalTime | `am force-stop` then `am start -W -n com.axialforge.cardkeep/.MainActivity` |
| Cold start, run 2 | 886 ms | same |
| Cold start, run 3 | 742 ms | same |
| APK arm64-v8a | 53.4 MB (55,989,997 B) | `audit/artifact` file size |
| APK armeabi-v7a | 41.7 MB (43,700,579 B) | same |
| APK x86_64 | 59.6 MB (62,510,818 B) | same |
| Memory idle (Contacts) | 86.9 MB PSS, 212.5 MB RSS, native heap 25.8 MB | `dumpsys meminfo` |
| Memory, Scan open (camera live) | 182.7 MB PSS, 313.3 MB RSS, native heap 99.2 MB | same |
| Memory after leaving Scan | 167.5 MB PSS (165.8 MB after 11 more screens) | same (MOB-PERF-0001) |
| Frames / jank | Not measurable: gfxinfo counted 4 frames only (Flutter surface) | `dumpsys gfxinfo ... reset`, scroll, read |
| Orientation | Not locked; landscape renders and scrolls | `user_rotation 1` |
| Font scale 1.3 / 2.0 | No clipping; long text wraps or ellipsizes | `settings put system font_scale` |
| Dark theme | Renders correctly | `cmd uimode night yes` |
| Touch targets < 48 dp | DiscButton 46 dp (MOB-A11Y-0001); scan mode 34 dp tall (MOB-A11Y-0002) | `uiautomator dump` bounds / 3.0 |
| Unlabelled icon buttons | none found | `uiautomator dump`, all screens |
| Back stack | 8 Back presses after visiting 9 drawer sections (MOB-UX-0001) | `input keyevent BACK` + `dumpsys window` |

## Key screenshots

![Empty Contacts with empty state](artifact/screens/01_launch_empty.png)
![Navigation drawer](artifact/screens/02_drawer.png)
![vCard import confirmation](artifact/screens/05_import_preview.png)
![New contact form](artifact/screens/08_edit_new.png)
![Contact detail with long name/title/company](artifact/screens/09_detail_long.png)
![Scan screen (emulator camera scene)](artifact/screens/13_scan.png)
![Sync to desktop placeholder](artifact/screens/27_Sync_to_desktop.png)
![Settings](artifact/screens/29_Settings.png)
![No NFC state](artifact/screens/30_Tap_cards_NFC.png)
![Landscape Contacts](artifact/screens/40_landscape_contacts.png)
![Landscape scrolled](artifact/screens/41_landscape_scrolled.png)
![Settings at font 1.3](artifact/screens/52_font130_settings.png)
![Detail at font 2.0](artifact/screens/54_font200_detail.png)
![Contacts at font 2.0](artifact/screens/55_font200_contacts.png)
![Dark detail](artifact/screens/61_dark_detail.png)
![Dark Export and backup](artifact/screens/62_dark_export.png)

## Not covered (BLOCKED)

Real device (Galaxy S25 Ultra) behaviour, NFC, real-camera OCR quality, API 24-35 devices, frame timing (needs a profile build + DevTools), and large-library scroll performance (release build cannot be seeded).
