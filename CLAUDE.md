# CardKeep (repo folder: Card Organizer)

CardKeep is a local-first business card organizer for Android first, then Windows, then iOS. You photograph or
tap a card, check what was read, and keep the person with their company, role history, events and follow-ups.
There is no account, no cloud and no background service: the data lives in one SQLite database on the device,
and the only network use is LAN sync between your own devices and an opt-in link fetch for NFC link cards.
The Dart package is still named `card_organizer`; the product name, app id (`com.axialforge.cardkeep`) and all
labels are CardKeep.

## Non-negotiables

- **Nothing leaves the device** unless the user turns it on (LAN sync, "Fetch details from link cards"). On-device
  OCR only. No analytics, telemetry or crash reporting service.
- **Every link opens in the default app** via `LinkLauncher` (`url_launcher`, external mode): web, tel, sms,
  mailto, maps. No in-app web view.
- **Never hard-delete** outside the purge job. Deletes are tombstones (`deleted_at`) so sync can propagate them.
- **Only repositories write tables.** UI talks to `ContactsRepository` / `SettingsRepository`, which keep
  `updated_at`, tombstones and the search index right.
- **Former and bounced contact points are history**, never the default call/email/text target.
- **Side drawer only**, no bottom tabs. Light theme. Tokens in `lib/app/theme.dart`; brand orange/ivory/charcoal
  from `design/branding/`.
- Use the full word "cumulative" in reports.

## Commands

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # after any table change
flutter analyze
flutter test
flutter build apk --debug --target-platform android-x64     # emulator build
```

On this PC every Gradle build needs `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:/tmpj` set first (see Gotchas).
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
| `lib/features/<area>/` | Screens: contacts (list, detail, edit), settings, placeholder, debug OCR capture |
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
- **Variable fonts** — Newsreader and Hanken Grotesk are variable TTFs; weight must be set with
  `FontVariation('wght', …)` (see `_t()` in `theme.dart`), `fontWeight` alone renders regular.
- **csv 8.x dropped `ListToCsvConverter`**; CSV quoting is hand-written (RFC 4180) in `csv_export.dart`.
- **ML Kit is Android/iOS only**, so `.ocr.json` fixtures come from the phone (debug OCR capture screen). The
  parser itself is pure Dart and tested on the desktop.

## Unverified

ML Kit per-line confidence on a real phone. Scan thresholds (blur 80, glare 1.5%, 45% frame, 1400 px) are starting
values to tune with real cards.
