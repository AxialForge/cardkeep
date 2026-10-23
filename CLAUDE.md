# CardKeep (repo folder: Card Organizer)

CardKeep is a local-first business card organizer for Android first, then Windows, then iOS. You photograph or
tap a card, check what was read, and keep the person with their company, role history, events and follow-ups.
There is no account, no cloud and no background service: the data lives in one SQLite database on the device,
and the only network use is LAN sync between your own devices and an opt-in link fetch for NFC link cards.
The Dart package is still named `card_organizer`; the product name, app id (`com.axialforge.cardkeep`) and all
labels are CardKeep.

## Non-negotiables

- **Nothing leaves the device** unless the user turns it on (LAN sync, "Fetch details from link cards", the update
  check: a manual button plus an opt-in startup check, off by default). On-device OCR only. No analytics, telemetry or crash reporting service.
- **Every link opens in the default app** via `LinkLauncher` (`url_launcher`, external mode): web, tel, sms,
  mailto, maps. No in-app web view.
- **Never hard-delete** outside the purge job. Deletes are tombstones (`deleted_at`) so sync can propagate them.
- **Only repositories write tables.** UI talks to `ContactsRepository` / `SettingsRepository`, which keep
  `updated_at`, tombstones and the search index right.
- **Former and bounced contact points are history**, never the default call/email/text target.
- **Side drawer only**, no bottom tabs. Themes: two looks, each with a light and a dark palette (CardKeep =
  Light/Dark, Navy and brass), all palettes in `lib/app/theme.dart`, paired in `lib/app/theme_family.dart`; Settings shows
  them as theme pills (`lib/kit/theme_pill.dart`, shared with Pagemark). Saved choice ids: a palette id, `system`, or
  `system:<familyId>`. Colour roles: `ink` = text, `strong` = dark headers/banners, `action` = orange primary controls,
  `brass`/`brassText` = accent. Never use `Colors.white`/`ink` as a background; use the role.
- Use the full word "cumulative" in reports.

## Commands

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # after any table change
flutter analyze
flutter test
flutter build apk --debug --target-platform android-x64     # emulator build
```

On this PC every Gradle build needs `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:/tmpj`, and (for OpenCV)
`ANDROID_HOME=C:\Android\sdk` and `ANDROID_NDK_HOME=C:\Android\sdk
dk8.2.13676358`, set first (see Gotchas).
`adb` is not on PATH: `C:\Android\sdk\platform-tools\adb.exe`. Emulator: `Pixel_10_Pro_XL_test`.
`tool/emu.ps1` builds, installs, seeds demo data and screenshots on the emulator.

## Architecture

| Path | What |
|---|---|
| `lib/main.dart` | Opens the database, registers font licences, starts the app inside `ProviderScope` |
| `lib/app/` | `app.dart` (MaterialApp.router), `router.dart` (go_router), `drawer.dart` (destinations + milestone stubs), `theme.dart` (palettes, tokens, fonts), `widgets.dart` (Panel, Pill, Avatar, DiscButton, EmptyState, confirm), `providers.dart` (Riverpod) |
| `lib/core/db/` | drift tables (`tables.dart`), database + FTS5 `person_search` (`database.dart`), generated `database.g.dart` |
| `lib/core/contacts/` | `ContactsRepository` (all contact writes, search, stats), view models and `ContactDraft` |
| `lib/core/settings/` | `SettingsRepository` over the `app_settings` key/value table; `SearchEngine` |
| `lib/core/links/` | `LinkLauncher`: the only way out to other apps |
| `lib/core/vcard/`, `lib/core/csv/` | vCard 3.0/4.0 and CSV (generic, HubSpot, Salesforce) writers |
| `lib/core/text/` | Matching keys: `companyKey`, `nameKey`, `digitsOnly` |
| `lib/parser/` | Pure-Dart card parser (`rules.dart`), OCR model (`ocr.dart`), ML Kit adapter |
| `lib/scan/` | `geometry.dart` (quads, card aspects), `quality.dart` (gates, hints, auto-capture), `card_detector.dart` (OpenCV: detect, rectify, enhance, crop), `scan_pipeline.dart` (`ScannedSide`, store → OCR + QR → parse, auto-save rule), `qr_content.dart` (QR classify, link checks, structured merge), `scan_worker.dart` (batch reader, crash recovery) |
| `lib/core/cards/` | `CardQueueRepository`: the review queue over the `cards` table |
| `lib/core/images/` | `ImageStore`: card JPEGs by sha256 (original, rectified, thumb, pending) |
| `lib/features/<area>/` | Screens: contacts (list, detail, edit), scan (camera, capture sheet, results, manual crop), settings, placeholder, debug OCR capture |
| `test/` | Repository, schema, parser, writers, widget flow tests; `test/cards/` real-card ground truth (git-ignored); `tool_seed_demo_test.dart` writes the demo database |
| `docs/` | Spec v0.2, scanning deep dive, `ROADMAP.md` (sections S0–S17, milestones M1–M9), `_tools/` PDF builder |
| `design/` | Executive mockups (`*.dc.html`), `branding/` (CardKeep logo sources and prompts) |
| `Documentation/` | Finished PDFs/Word, named `<name> Rev x.y` |

### Core extension point

A new screen is a route in `lib/app/router.dart` plus, if it belongs in the drawer, a `Destination` in
`lib/app/drawer.dart`. A destination with `milestone:` set shows the "arrives in version x" placeholder until its
section is built; remove the milestone when the screen lands. Data access goes through a repository method, never
direct table writes from a widget.

## Roadmap and testing

Work follows `docs/ROADMAP.md` section by section. Each section: build, unit/widget tests, `flutter analyze` clean,
emulator check with screenshots, commit. A milestone ends with a version tag, a GitHub Release with APKs, and a
phone test sheet in `docs/phone-tests/`; the owner tests on a real phone only then.

## Gotchas

- **JDK 25 loopback error** — `flutter build apk` fails with "Unable to establish loopback connection". Android
  Studio's JBR (JDK 25) puts its selector pipe socket in the 8.3 short temp path, which fails. Fix: set
  `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:/tmpj` (also in `android/gradle.properties`). Overriding
  `java.io.tmpdir` does not help.
- **PowerShell 5.1 mangles UTF-8** — `Get-Content`/`Set-Content` read BOM-less UTF-8 as ANSI and write mojibake
  (é, –, ’ inside regexes broke the parser once). Edit with the Edit tool or Python with `encoding='utf-8'`. Python
  string literals with `\a`, `\b` in Windows paths turn into control characters; use raw strings.
- **drift copies `clientDefault` closures into `database.g.dart`**, so anything they call must be public
  (`uuidGen`, not `_uuid`).
- **drift in widget tests**: `await db.close()` inside a `testWidgets` body hangs forever (fake-async zone), and
  repository writes before `pumpWidget` must go through `tester.runAsync`. Close in `tearDown`, and end each test
  with `pumpWidget(SizedBox())` + `pump(1 s)` so drift's stream-cancel timer fires. See `contacts_flow_test.dart`.
- **FTS5 matches prefixes only.** Phone search for "555-0142" found nothing until the index also stored the 7- and
  4-digit tails of every number (`_phoneTerms`). Don't "fix" it with `LIKE '%…%'`; that loses the index.
- **Phones are stored E.164** (`+13305550142`); matching compares them exactly. Format only for display
  (`formatPhone`). Numbers that don't parse for the region are kept as typed.
- **`Panel` must be a `Material`**, not a decorated `Container`: ListTiles inside a coloured Container lose their
  ink and selection colour (Flutter asserts in debug).
- **Colours are getters, not consts.** `Tokens.ink` etc. read `AppPalette.current`, so a widget using them can't be
  `const`. Switching palette re-marks every element for rebuild (`_rebuildAll` in `app.dart`); a widget that caches a
  colour in a field or `static final` will keep the old palette.
- **Release signing key** is in `keys/` (git-ignored) with a copy in `%USERPROFILE%\.android-keys`; CI uses repo
  secrets. Set secrets with `gh secret set --body …` — piping from PowerShell 5.1 adds CRLF and broke the base64 keystore.
- **OpenCV compiles from source** (`opencv_dart` 2.x build hook, CMake). Android builds fail with "Bad state: No
  element" in `androidToolchainCmake` unless `ANDROID_NDK_HOME` (and `ANDROID_HOME`) are set; the first build takes a
  few minutes, later ones are cached. CI installs the NDK and Ninja for the same reason.
- **`compileSdk = 37`** is required by `permission_handler` 13; it doesn't change which phones can install.
- **Camera vs. system sheets**: the permission dialog and the photo picker pause the activity. Starting the camera
  twice (pause/resume mid-start) over-binds CameraX ("No supported surface combination"); a live image stream while
  Android tears the surface down behind the picker crashes the engine ("FlutterJNI is not attached"). The scanner
  guards `_start` with `_starting` and fully releases the camera before opening the picker, then restarts it.
- **Exposure gates use percentiles (1st/99th), not the mean**: a white card's mean is "overexposed" and a black card's
  "too dark". Glare counts clipped pixels (>= 253) only; white paper sits at 240-250.
- **Emulator screenshots** go to `/data/local/tmp`, never `/sdcard`: shared-storage files appear in the photo picker
  and shift the grid the tap coordinates rely on. The emulator's own photo picker sometimes crashes ("Key 3 was
  already used"); that's the system app, retry.
- **Release builds need `INTERNET` declared** for the updater; Flutter only adds it to debug builds, so updates
  "work" in debug and fail silently in release without it. `REQUEST_INSTALL_PACKAGES` must come out of the Play
  build (S17.9). The repo is public so the unauthenticated releases API works.
- **Opening a .vcf showed "Page Not Found".** Flutter treats every VIEW intent as a deep link and routes its
  `content://` address through go_router. `flutter_deeplinking_enabled=false` in the manifest turns that off;
  `MainActivity` reads the file and hands it over on the `cardkeep/incoming` channel. Testing with `adb shell am
  start -d content://...` fails (no read grant); open it from the Files app or the in-app picker.
- **Restore swaps files before the database opens.** `Backups.stage` unpacks into `restore_pending/`;
  `applyPendingRestore` in `main()` moves the old database and `cards/` to `before_restore/` and the backup in. The
  app exits after staging, so it reopens on the restored data.
- **Testing reminders on the emulator:** `am force-stop` clears the app's posted notifications, so a "tap the
  reminder" test after `Stop-App` finds nothing. Use `am kill` (background process only) instead. Reminders use
  inexact alarms (no exact-alarm permission); Android's window is ~75% of the delay, capped at 1 h, so a test due in
  2-3 minutes arrives within a minute or two. To set one close, pull the db with `run-as ... cat` through `cmd /c`
  (PowerShell `>` corrupts binary), edit `followup_at` (unix seconds), push it back.
- **R8 strips ML Kit in release builds.** ML Kit finds its components by reflection; R8 removed the
  `ComponentRegistrar` constructors, so in 0.2.0 and 0.2.1 release APKs every OCR/QR call threw a
  NullPointerException ("Could not instantiate ... TextRegistrar" at startup) and the scanner looped on "Reading
  card...". Debug builds aren't shrunk, so the emulator never showed it. Keep rules are in
  `android/app/proguard-rules.pro`; before a release, run a **release** build on the emulator or phone and scan
  once. A failing reader must never loop: `_readSafely` keeps the card without text.
- **go_router never completes a push that was replaced.** The review screen saves with `pushReplacement`
  (review → contact), so `await context.push('/contact/new')` from the scanner hung forever and left the camera off.
  Screens that open others they don't need a result from use `unawaited(context.push(...))`; the scanner frees and
  restarts the camera from `RouteAware` (`didPushNext`/`didPopNext`, `routeObserver` in `router.dart`).
- **ML Kit reports per-line confidence** (about 0.82–0.91 on clear print). Field confidence is the deep-dive
  weighted sum (0.5 OCR + 0.3 rule + 0.2 cross-check, `_Line.score`); multiplying rule × OCR kept every card under the
  0.85 auto-save bar. Fixtures without confidence score on the rule alone.
- **Parse on the unmodified line.** Cutting a matched phone out of `l.rest` before reading the next number's label
  shifted positions and dropped "O" labels on "M … O …" lines (`test/fixtures/mlkit_dana_two_phones.json`).
- **The review queue is the `cards` table**: `person_id IS NULL` = waiting. `ocr_json` holds
  `{front, back?, auto?}` with the OCR lines, QR text, issues and region; parse and QR merge are recomputed on load,
  so parser fixes also improve cards already waiting.
- **Variable fonts** — Newsreader and Hanken Grotesk are variable TTFs; weight must be set with
  `FontVariation('wght', …)` (see `_t()` in `theme.dart`), `fontWeight` alone renders regular.
- **csv 8.x dropped `ListToCsvConverter`**; CSV quoting is hand-written (RFC 4180) in `csv_export.dart`.
- **ML Kit is Android/iOS only**, so `.ocr.json` fixtures come from the phone (debug OCR capture screen). The
  parser itself is pure Dart and tested on the desktop.

## Unverified

ML Kit per-line confidence on a real phone. Scan thresholds (blur 80, glare 1.5%, 45% frame, 1400 px) are starting
values to tune with real cards.
