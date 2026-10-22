# CardKeep Roadmap

(Product renamed from Card Organizer to **CardKeep** on 2026-10-19; app id `com.axialforge.cardkeep`.)

Local-first business card organizer. Flutter, Android first, then iOS, then Windows.
Sources: spec v0.2 (`docs/card-organizer-spec-v0.2.md`), scanning deep dive (`docs/card-organizer-scanning-deep-dive.md`),
25 executive mockups (`design/executive/`). Written 2026-10-19.

## How to use this roadmap

- The work is split into **18 sections** (S0 to S17). Each section has a goal, dependencies, a task list with IDs, the tests,
  the emulator checks, and a definition of done. Say "do S5" to build one section, or "do S5 to S7" to build several in a row.
- Sections are grouped into **9 milestones** (M1 to M9). A milestone ends with a version tag, a GitHub push and an APK.
  **That is when you test on your phone.** Between milestones, everything is checked on the emulator `Pixel_10_Pro_XL_test`.
- Every milestone ships with a **phone test sheet**: the things the emulator cannot check (real camera, NFC, notifications,
  fingerprint, performance on real hardware).
- Task IDs are stable (`S5.3`). Commits and the changelog refer to them.
- Status marks: **[x]** done, **[ ]** to do, **[~]** partly done, **[?]** needs a decision from you.
- Every section follows the same loop: plan, build, unit/widget tests, `flutter analyze` clean, emulator check, commit.

### Status at a glance

| Section | Name | Milestone | Status |
|---|---|---|---|
| S0 | Project foundation | M1 | done (repo + CI secrets at push) |
| S1 | Data layer | M1 | partly done (M1 parts done) |
| S2 | Parser and OCR adapter | M1 | partly done (needs your 40-card set) |
| S3 | App shell, theme and navigation | M1 | done |
| S4 | Contacts: list, detail, edit | M1 | done |
| S5 | Camera scanner and card detection | M2 | done (live capture to verify on a phone) |
| S6 | QR on cards | M2 | done |
| S7 | Review, queue and batch | M2 | done (speed to verify on a phone) |
| S8 | Duplicates and merge | M3 | done |
| S9 | Tags | M3 | done |
| S10 | Events and scan sessions | M3 | done (S10.6, S10.8 later) |
| S11 | Follow-ups and notifications | M3 | done |
| S12 | Career tracking | M4 | done |
| S13 | Import, export, backup, My card | M5 | done (S13.6, S13.12 later) |
| S14 | NFC tap cards | M6 | to do |
| S15 | Settings, security, onboarding, states | M7 | to do |
| S16 | Sync and Windows desktop | M8 | to do |
| S17 | Release 1.0 | M9 | to do |

### Milestones

| Milestone | Version | Sections | What you can do on your phone after it |
|---|---|---|---|
| M1 Contacts core | 0.1.0 | S0 to S4 | Add, edit, search, call, email, open websites. Debug OCR capture tool for the test set. |
| M2 Scanning | 0.2.0 | S5 to S7 | Photograph cards (one or a pile), read QR codes, review and save, batch with a review queue. |
| M3 Organise | 0.3.0 | S8 to S11 | Find and merge duplicates, tag, run events with scan sessions, get follow-up reminders. |
| M4 Career | 0.4.0 | S12 | See job changes and retirements, keep role history, link replacements. |
| M5 Data in and out | 0.5.0 | S13 | Import vCard/CSV/phone contacts, export CRM CSVs, back up and restore, share your own card. |
| M6 Tap cards | 0.6.0 | S14 | Read NFC business cards (vCard and link cards). |
| M7 Lock-down | 0.7.0 | S15 | App lock, encrypted database, full Settings, first-run welcome, polished empty and error states. |
| M8 Desktop | 0.8.0 | S16 | Sync phone and Windows PC over the LAN with a QR pairing. |
| M9 Release | 1.0.0 | S17 | Play Store closed test, then production. Full documentation set. |

### Dependency map

```
S0 -> S1 -> S2 ----------------------> S7
         \-> S3 -> S4 -> S5 -> S6 ---> S7 -> S8 -> S12
                      \-> S9                \-> S10 -> S11
                      \-> S13 (needs S8 for import matching)
                      \-> S14 (needs S7 review, S8 matching)
S15 can start after S4 (settings shell) and finishes after S14.
S16 needs every table final (after S15). S17 is last.
```

Parallel-safe pairs (can be bulk-built together without touching the same files): S9 + S10, S13 + S14, S11 + S12 after S10.

---

## M1 Contacts core (0.1.0)

### S0 Project foundation

**Goal:** a repo you can build, test and release from, to the AxialForge conventions.
**Depends on:** nothing.

| ID | Task | Status |
|---|---|---|
| S0.1 | Flutter project `card_organizer`, org `com.axialforge`, platforms android, ios, windows | [x] |
| S0.2 | Handoff package copied in: docs/, design/, deck/, CLAUDE.md | [x] |
| S0.3 | `Documentation/` folder with README (finished PDFs/Word, named `<name> Rev x.y`) | [x] |
| S0.4 | Local git repo, first commits authored as AxialForge, no stale local identity | [x] |
| S0.5 | JDK 25 loopback fix in `android/gradle.properties` (`-Djdk.net.unixdomain.tmpdir=C:/tmpj`) | [x] |
| S0.6 | `.gitignore`: real card photos (`test/cards/*`) never committed | [x] |
| S0.7 | Project `CLAUDE.md` rewritten to house style: one-paragraph summary, non-negotiables, commands, architecture map with directory table, core extension point, Gotchas | [~] gotchas started |
| S0.8 | Files the template requires: `README.md` (real one), `CHANGELOG.md` (Keep a Changelog), `LICENSE` [?], `CONVENTIONS.md` link, `SETUP.md` worked through and deleted | [ ] |
| S0.9 | Version in `pubspec.yaml` only (`0.1.0+1`); build number rule: +1 per release | [ ] |
| S0.10 | `analysis_options.yaml`: flutter_lints plus strict casts, strict raw types, `prefer_const`, `avoid_print` (tests exempt) | [ ] |
| S0.11 | CI: `.github/workflows/ci.yml` runs `flutter analyze` and `flutter test` on push and PR (Ubuntu runner, Flutter pinned to 3.47) | [ ] |
| S0.12 | CI: `.github/workflows/release.yml` on tag `vX.Y.Z` builds split-per-ABI release APKs (arm64-v8a, armeabi-v7a, x86_64) and attaches them to a GitHub Release with the changelog section as notes | [ ] |
| S0.13 | Release signing: upload keystore created locally, stored outside the repo; `key.properties` git-ignored; CI reads it from GitHub secrets (base64 keystore + passwords) | [ ] |
| S0.14 | App id final check: `com.axialforge.card_organizer` (cannot change after Play upload) [?] | [ ] |
| S0.15 | App display name [?] "Card Organizer" or another name (no "Forge" in the name) | [ ] |
| S0.16 | GitHub repo `AxialForge/card-organizer`, private until M9 [?], description and topics | [ ] |
| S0.17 | `tool/emu.ps1` helper: boot emulator, build x86_64 debug APK, install, launch, screenshot, tap, swipe, type (same pattern as Pagemark) | [ ] |
| S0.19 | In-app updater for GitHub APKs (Settings → Updates; public repo; opt-in startup check) | [x] |
| S0.18 | `tool/seed_demo_test.dart`: writes a demo database with fictional contacts for emulator checks and screenshots | [ ] |

**Done when:** a pushed commit goes green in CI, and pushing a test tag produces a GitHub Release with three APKs.

### S1 Data layer

**Goal:** every table from spec section 3, repositories the UI talks to, and the writers.
**Depends on:** S0.

| ID | Task | Status |
|---|---|---|
| S1.1 | drift schema: people, companies, roles, contact_points, successions, change_suggestions, cards, events, scan_sessions, tags, person_tags, devices | [x] |
| S1.2 | Common columns on every table: uuid PK, created_at, updated_at, deleted_at (tombstone) | [x] |
| S1.3 | Foreign keys on, indexes on company name_norm, contact value, role person | [x] |
| S1.4 | vCard 3.0/4.0 writer (escaping, CRLF, 75-octet folding) | [x] |
| S1.5 | CSV writer: generic, HubSpot, Salesforce column sets, RFC 4180 quoting | [x] |
| S1.6 | `updated_at` maintained automatically on every update (repository layer, not the UI) | [ ] |
| S1.7 | Composite unique key on person_tags (person_id, tag_id); add `card_side` and `kind` columns needed by S5 (rectified/original/thumb hashes) | [ ] |
| S1.8 | Settings table (key/value, synced flag per key) for everything in S15 | [ ] |
| S1.9 | Schema versioning: `drift_dev schema dump` per version into `drift_schemas/`, generated migration tests (`schema steps`) so every upgrade path is tested | [ ] |
| S1.10 | Repositories: `PeopleRepo`, `CompanyRepo`, `RoleRepo`, `ContactPointRepo`, `CardRepo`, `EventRepo`, `TagRepo`, `SuggestionRepo`. UI never writes tables directly | [ ] |
| S1.11 | `PersonView` read model: person + current role + company + primary phone/email + tags + met-at event, one query, watched as a stream | [ ] |
| S1.12 | Company normaliser: lower case, punctuation removed, legal suffix removed ("Halden Tooling Group" = "Halden Tooling") | [ ] |
| S1.13 | Image store: files on disk named by sha256 under app documents `images/`; original (JPEG q90), rectified (q85), thumbnail (400 px); EXIF stripped | [ ] |
| S1.14 | Purge job: tombstoned rows older than the purge window and not pending sync are hard-deleted with their orphaned images (runs at app start, never in the background) | [ ] |
| S1.15 | Full-text search: FTS5 table over name, company, title, notes, emails, phones; kept in sync with triggers | [ ] |
| S1.16 | vCard reader (2.1, 3.0, 4.0; folded lines; quoted-printable in 2.1; charset; size caps 8 KB tag / 1 MB file; control characters stripped) | [ ] |
| S1.17 | CSV reader with header detection and column mapping model (used in S13) | [ ] |
| S1.18 | vCard 4.0 `ALTID`/`LANGUAGE` and 3.0 `X-` properties for second-language names | [ ] |

**Tests:** schema test (in-memory), migration tests per version, round-trip vCard write then read for 20 fixtures, CSV round-trip, normaliser table test, FTS search test.
**Done when:** all repositories have tests, a fresh install and every upgrade path are covered.

### S2 Parser and OCR adapter

**Goal:** turn OCR lines into fields with confidence, measured against your real cards.
**Depends on:** S1 (models).

| ID | Task | Status |
|---|---|---|
| S2.1 | Pure-Dart `OcrPage`/`OcrLine` model with JSON (fixtures) | [x] |
| S2.2 | ML Kit adapter behind `OcrAdapter` (parser never imports ML Kit) | [x] |
| S2.3 | Rules: email, website, phones (E.164 via phone_numbers_parser, label tokens, fax to notes), address (US/CA/UK/EU postal), title keywords, name (tallest 2 to 4 capitalised tokens, credentials to suffix), company (legal suffix, domain match, fallback), notes | [x] |
| S2.4 | Ground-truth harness: per-field accuracy, targets enforced at 40 cards | [x] |
| S2.5 | Debug OCR capture screen: pick or take photos, writes `.jpg`, `.ocr.json`, `.draft.json` | [x] |
| S2.6 | ML Kit per-line confidence: confirmed present (0.82-0.91 on clear text, emulator 2026-10-20) | [x] |
| S2.7 | Confidence formula from the deep dive: 0.5 x OCR + 0.3 x rule score + 0.2 x cross-check | [x] |
| S2.8 | Global assignment pass: score every line for every field, then assign so each single-value field is used once (replaces first-match order) | [ ] |
| S2.9 | Block grouping by position (lines close together form a block; used by Review boxes) | [ ] |
| S2.10 | Phone extensions ("x123", "ext. 123"), direct-line label (D, Direct), multiple phones per label | [ ] |
| S2.11 | OCR fix-ups: O/0 and l/1/I inside numbers and emails, "@" misreads, spaces inside emails, "rn" vs "m" | [~] emails done |
| S2.12 | Name splitting: Western order, "Last, First", particles (van, de, da), keep display name exactly as printed | [ ] |
| S2.13 | URL normalisation: https added, "www" kept only for display, tracking parameters dropped | [ ] |
| S2.14 | Region choice: event location first, then device locale | [ ] |
| S2.15 | Two-sided merge: back side parsed separately, fields merged, conflicts flagged | [ ] |
| S2.16 | Second script: Latin + Japanese/Chinese/Korean/Devanagari model, lines merged by position | [ ] |
| S2.17 | Orientation: rotate by ML Kit line angles before parsing (vertical and upside-down cards) | [ ] |
| S2.18 | Test set built with you: 40 cards (10 plain, 8 dark, 6 glossy, 6 vertical, 5 two-sided, 5 non-English) | [ ] needs your photos |
| S2.19 | Tune rules until targets met: email/phone 98%, name 92%, company 90%, title 85% | [ ] |
| S2.20 | Parser runs in CI on every change (ground truth stays local because it holds real people's data; CI runs the synthetic set) | [ ] |

**Emulator check:** push 3 sample card images to the emulator gallery, pick them in the capture tool, confirm files are written.
**Done when:** your 40-card set meets all targets.

### S3 App shell, theme and navigation

**Goal:** the executive look from the mockups and the side drawer.
**Depends on:** S0.

| ID | Task | Status |
|---|---|---|
| S3.1 | Design tokens as a `ThemeExtension`: ground #F3F4F6, surface #FFFFFF, ink #0E1A2B, ink2 #4A5568, hairline #E2E5EA, brass #B08A4A (text #7A5B22), amber #FBF1DC/#7A4E0B, Hot #F8E1DD/#8C2F1F, Cold #E1EAF5/#1F4A78 | [ ] |
| S3.2 | Fonts bundled (not downloaded): Newsreader (display), Hanken Grotesk (UI); OFL licence files included | [ ] |
| S3.3 | Type scale, spacing scale, radius, hairline borders, elevation rules taken from the mockups | [ ] |
| S3.4 | Side drawer (flat, no bottom tabs) with every destination from Menu.dc.html, counts on Review queue and Follow-ups | [ ] |
| S3.5 | Router (go_router): named routes for all 25 screens, deep links for contact and event ids | [ ] |
| S3.6 | State management: Riverpod providers over the repositories (one pattern, used everywhere) | [ ] |
| S3.7 | Shared widgets: lead-rating chip (Hot/Warm/Cold), confidence dot, amber field, section header, hairline list tile, avatar with initials, card thumbnail, empty state, error banner, confirm sheet | [ ] |
| S3.8 | Light theme only (spec). Contrast checked for every token pair (WCAG AA) | [ ] |
| S3.9 | Text scaling to 200% without clipping; tap targets 48 dp; TalkBack labels on icon buttons | [ ] |
| S3.10 | Link launcher: one helper, `LaunchMode.externalApplication` for web, tel:, sms:, mailto:, maps; Android 11+ `<queries>` for https, tel, mailto, sms | [ ] |
| S3.11 | App icon and splash (placeholder until S17 artwork) | [ ] |
| S3.12 | Debug menu entry for the OCR capture tool (debug builds only) | [ ] |

**Tests:** widget golden tests of the drawer and shared widgets; launcher unit test with a fake.
**Emulator check:** screenshot each drawer destination stub, font scale 2.0 screenshot.

### S4 Contacts: list, detail, edit

**Goal:** a useful address book before any scanning exists. Mockups: Main, Detail, ContactEdit.
**Depends on:** S1, S3.

| ID | Task | Status |
|---|---|---|
| S4.1 | Contacts list: sort by last name, company, recently added, recently met; alphabet index scrubber | [ ] |
| S4.2 | Search (FTS) across name, company, title, phone, email, notes; results as you type | [ ] |
| S4.3 | Filters: tag, event, lead rating, status (active/moved/retired), has follow-up | [ ] |
| S4.4 | List row: avatar/thumbnail, name, title at company, rating chip, status badge for moved/retired | [ ] |
| S4.5 | Multi-select: tag, rate, export, delete | [ ] |
| S4.6 | Detail: card image (front/back flip, zoom), name, title, company, contact points with call/text/email/web/map buttons, notes, tags, met-at event, introduced-by, follow-up, role history (S12 fills it) | [ ] |
| S4.7 | Former and bounced contact points shown struck through and never used as the default action | [ ] |
| S4.8 | "Check on web": opens "{first} {last} {company}" search in the default browser using the chosen search engine | [ ] |
| S4.9 | Edit: all fields, multiple phones/emails with labels, primary marker, company autocomplete from existing companies, title autocomplete, validation (email format, phone parse with E.164 preview) | [ ] |
| S4.10 | New contact by hand (manual source) | [ ] |
| S4.11 | Delete: tombstone, undo snackbar for 5 s | [ ] |
| S4.12 | Lead rating set from list swipe or detail | [ ] |
| S4.13 | Notes with timestamps (simple log: "2026-10-19 Called, wants a quote") | [ ] |
| S4.14 | Share one contact as vCard (system share sheet) | [ ] |
| S4.15 | Performance: list of 5,000 seeded contacts scrolls at 60 fps, search under 100 ms | [ ] |

**Tests:** widget tests for list, search, detail actions (fake launcher), edit validation.
**Emulator check:** seeded 50-contact database, add/edit/delete flow, call and email buttons open the dialer and mail app, screenshots.

### M1 release

| ID | Task |
|---|---|
| M1.1 | CHANGELOG 0.1.0, version bump, tag `v0.1.0`, GitHub Release with APKs |
| M1.2 | Phone test sheet 0.1.0: install from the Release APK, add contacts, call/text/email/web/maps from detail, search, font size large, OCR capture tool on 5 real cards (record whether ML Kit gives line confidence) |
| M1.3 | Fix list from your phone test goes into 0.1.1 or the next section |

---

## M2 Scanning (0.2.0)

### S5 Camera scanner and card detection

**Goal:** point the phone at a card (or a pile) and get a flat, sharp image. Mockup: Scan.
**Depends on:** S4, S2.

| ID | Task | Status |
|---|---|---|
| S5.1 | Package choice: `camera` (official; decision D4) | [x] |
| S5.2 | Camera permission flow with rationale; denied and permanently-denied states (link to settings) | [x] |
| S5.3 | Preview 1080p, still at max resolution, tap-to-focus, continuous autofocus, torch toggle, exposure lock on first detection | [x] |
| S5.4 | `opencv_dart` in a worker isolate: downscale to 640 px, grey, blur, Canny, close, contours, 4-point convex quads | [x] |
| S5.5 | Quad scoring by aspect ratio: US 1.75, EU 1.545, Japan 1.65, portrait versions | [x] |
| S5.6 | Live overlay of the detected quad; hint line ("Move closer", "Hold steady", "Glare, tilt the card", "More light", "Card cut off"), one at a time by priority | [x] |
| S5.7 | Quality gates: size >= 45% of frame, Laplacian variance >= 80, glare < 1.5%, exposure 70 to 200, rectified long edge >= 1400 px, skew < 5% | [x] |
| S5.8 | Auto-capture when quad found, steady 400 ms, all gates pass; manual shutter always works | [x] |
| S5.9 | Perspective warp to a flat rectangle; save original + rectified + thumbnail before anything else runs (never lose a capture) | [x] |
| S5.10 | Manual 4-corner crop with magnifier handles when no quad is found | [x] |
| S5.11 | Back side: "Add back" after the front, linked to the same card | [x] |
| S5.12 | Multi-card shot (pile mode): detect 2 to 6 quads, rectify each, warn if a card is under 1400 px | [x] |
| S5.13 | Import from gallery (single and multiple) through the same pipeline | [x] |
| S5.14 | Preprocessing: OCR pass 1 as-is; pass 2 with CLAHE and, for dark cards, inverted; keep the better pass per line; cap 2000 px | [x] |
| S5.15 | Failed gates on the saved still never block; they set reason chips ("Blurry", "Glare") for the queue | [x] |
| S5.16 | Performance budget: capture to Review <= 2.5 s, OCR <= 800 ms, memory <= 300 MB | [~] measure on a phone |
| S5.17 | Event chip on the scan screen when a scan session is active (S10 wires it) | [ ] S10 |

**Tests:** quad detection on 30 fixture photos (hit rate >= 97% plain, >= 90% busy backgrounds), gate functions on fixture images, pipeline state tests.
**Emulator check:** emulator virtual camera scene for the permission and UI flow; gallery import of pushed card photos for the pipeline. Real camera is a phone-test item.

### S6 QR on cards

**Goal:** a vCard or MECARD QR beats OCR. Mockup: Scan (QR badge).
**Depends on:** S5.

| ID | Task | Status |
|---|---|---|
| S6.1 | `google_mlkit_barcode_scanning` on each straightened card (stills; preview-frame scanning not needed) | [x] |
| S6.2 | Contact payloads (vCard, MECARD) become a structured `CardCandidate` (source: qr) | [x] |
| S6.3 | URL QR treated like an NFC link card (open in browser / save link only) | [x] |
| S6.4 | Non-contact QR (Wi-Fi, SMS, app store) ignored unless tapped | [x] |
| S6.5 | Unified `CardCandidate` model (sources: qr, nfc_vcard, nfc_link, ocr) with per-field confidence | [x] |
| S6.6 | Merge rule: structured source wins, OCR fills gaps, disagreements flagged amber | [x] |
| S6.7 | URL safety: show domain large, flag punycode, lookalike characters and known shorteners before "Open" | [x] |

**Tests:** MECARD and vCard QR payload fixtures, merge-rule tests.

### S7 Review, queue and batch

**Goal:** check and fix what the scanner read, fast. Mockups: Review, Queue.
**Depends on:** S5, S6, S2.

| ID | Task | Status |
|---|---|---|
| S7.1 | Review screen: card image on top with coloured boxes per assigned block; fields below with confidence dots; amber fields first | [x] |
| S7.2 | Tap a box to reassign it to a field; tap empty text to create a block | [x] |
| S7.3 | "Rescan region": pinch to a crop, OCR only that crop | [x] |
| S7.4 | Company and title autocomplete from existing contacts | [x] |
| S7.5 | Right keyboards for email and phone; phone shows E.164 and invalid warning | [x] |
| S7.6 | Save: creates person, company, role (source scan), contact points, card row with hashes and OCR JSON | [x] |
| S7.7 | Save runs the match (S8 hook): duplicate goes to Merge, different company goes to Possible job change (S12 hook); before S8/S12 exist the hook is a no-op | [~] hook in place; S8 adds the match |
| S7.8 | Batch mode: capture continues while OCR runs in a worker isolate (queue depth 8, drops to 1 on low memory) | [x] |
| S7.9 | State machine: captured, rectifying, ocr, parsed, auto_saved or needs_review; persisted so a crash loses nothing | [x] |
| S7.10 | Auto-save rule: name + (phone or email), every required field >= 0.85, no match, setting on | [x] |
| S7.11 | Review queue: counts by state, reason chips (Low confidence, Possible duplicate, Blurry, Glare, Job change), swipe to discard with undo | [x] |
| S7.12 | Batch throughput >= 20 cards/min on a mid-range phone | [~] measure on a phone |

**Tests:** widget tests for reassigning blocks and saving; state-machine tests including restart mid-batch.
**Emulator check:** import 10 card photos in one go, watch queue fill, review two, screenshots.

### M2 release

Phone test sheet 0.2.0: 20 real cards in good light, dim light and with glare; a pile of 4 on a table; a QR card; a two-sided card;
record capture-to-review time; auto-capture feel; torch.

---

## M3 Organise (0.3.0)

### S8 Duplicates and merge

**Goal:** one person, one record. Mockups: Duplicates, Merge.
**Depends on:** S7.

| ID | Task | Status |
|---|---|---|
| S8.1 | Match rule in order: exact mobile (E.164); normalised name + same email local part; normalised name + Jaro-Winkler >= 0.9 on company or domain | [x] |
| S8.2 | Same company = duplicate; different company = job change (hands to S12) | [x] |
| S8.3 | Duplicates screen: pairs with match reason and score; scan the whole library on demand | [x] |
| S8.4 | Merge screen: side-by-side fields, pick per field, union of contact points/tags/cards/notes, keep both card images | [x] |
| S8.5 | Merge writes a tombstone for the loser and repoints every foreign key (roles, cards, tags, follow-ups, successions, events) | [x] |
| S8.6 | "Not a duplicate" remembered so the pair never shows again | [x] |
| S8.7 | Undo merge for the session (keeps the loser's snapshot until app close) | [x] |

**Tests:** matcher table tests (30 pairs), merge repointing test across every table.

### S9 Tags

**Goal:** your own groups. Mockup: Tags.
**Depends on:** S4.

| ID | Task | Status |
|---|---|---|
| S9.1 | Tags screen: create, rename, recolour (palette from tokens), delete with count warning | [x] |
| S9.2 | Assign tags from detail, edit and multi-select | [x] |
| S9.3 | Tag filter in Contacts; tag as an export scope (S13) | [x] |
| S9.4 | System tags: "Imported", "NFC link" (created on demand, renameable) | [x] |

### S10 Events and scan sessions

**Goal:** trade shows and networking with goals. Mockups: Events, EventDetail, NewEvent.
**Depends on:** S7.

| ID | Task | Status |
|---|---|---|
| S10.1 | Events list: upcoming, current, past; type badge (trade show / networking) | [x] |
| S10.2 | New/edit event: name, type, dates, location, booth/table, contact goal, notes, auto-start scan session, reminder offset days | [x] |
| S10.3 | Scan session: set the event once, every card scanned or tapped inherits it; active-event chip on Scan and Tap screens | [x] |
| S10.4 | Auto-start: session opens on the first event day when the app is opened (no background job) | [x] |
| S10.5 | Event detail: cards, contacts, companies, goal progress ring, follow-ups sent vs due (all queries, nothing stored) | [x] |
| S10.6 | Actions: draft follow-ups for the rest (S11), export event contacts (vCard/CSV, S13) | [~] follow-ups for everyone done; export waits for S13 |
| S10.7 | Contact "Met at" links back to the event; past events keep their contacts | [x] |
| S10.8 | Event location feeds the phone region for parsing (S2.14) | [ ] |

### S10b Owner requests (2026-10-20)

**Goal:** the list from the first real phone test. Done before S11.

| ID | Task | Status |
|---|---|---|
| S10b.1 | Phone extensions: parse "Ext. 112" / "x112" into an extension field; show and dial it (pause + digits) | [x] |
| S10b.2 | Fax numbers kept as their own kind (shown, exported, never the call target) | [x] |
| S10b.3 | ALL-CAPS names re-cased ("FRED PANETO" -> "Fred Paneto", keeps Mc/Mac/O'/hyphens) | [x] |
| S10b.4 | Middle name or initial field (optional), parsed from "Dana K. Reyes" | [x] |
| S10b.5 | Other card text sorted into labelled extra fields (slogans, licence numbers, hours) instead of only notes | [x] |
| S10b.6 | Company view: companies with several cards group their people; "Others at this company" on a contact | [x] |
| S10b.7 | Lead ratings optional: Settings switch and the edit page 3-dot menu; hidden everywhere when off | [x] |
| S10b.8 | Logo from the card (crop the largest graphic) as the contact's avatar, with remove/replace | [x] |
| S10b.9 | "+" opens a menu: Scan, Add by hand, Batch/pile ("raid"), Import a card file | [x] |
| S10b.10 | Name sort by first or last name (Settings and the sort control) | [x] |
| S10b.11 | Themes: drop Medium (too close to Light), add Navy and brass dark | [x] |

### S11 Follow-ups and notifications

**Goal:** never forget to follow up. Mockup: Followups.
**Depends on:** S10.

| ID | Task | Status |
|---|---|---|
| S11.1 | One `followup_at` per person; set from detail, review, event | [x] |
| S11.2 | Follow-ups list grouped Overdue, This week, Later; Done sets `followup_done_at` | [x] |
| S11.3 | Event reminders: end date + offset applied to every contact from the event | [x] |
| S11.4 | `flutter_local_notifications`: scheduled at the due date 8:00 local or the daily digest time; exact-alarm permission handling on Android 14+ | [x] inexact (no exact-alarm permission): up to ~1 h late; no daily digest yet |
| S11.5 | Manifest receivers for scheduled notifications (the Pagemark bug: missing receivers made every scheduled notification silent) | [x] |
| S11.6 | Re-schedule all on app start and after reboot (BOOT_COMPLETED receiver from the plugin) | [x] |
| S11.7 | POST_NOTIFICATIONS runtime permission (Android 13+) with rationale | [x] |
| S11.8 | Draft follow-up email: opens the mail app with subject and body template (mailto:), marks as sent on return only if you confirm | [x] |
| S11.9 | Notification tap opens the contact | [x] |

**Emulator check:** schedule a follow-up 2 minutes ahead and confirm the notification fires; reboot the emulator and confirm it is re-scheduled.

### M3 release

Phone test sheet 0.3.0: notification at the due time with the phone locked, after a reboot, with battery saver on; duplicate found
after rescanning a card; a short event with 10 cards and the goal ring.

---

## M4 Career (0.4.0)

### S12 Career tracking

**Goal:** know when people move or retire, keep the history, find the replacement. Mockups: Career, JobChange, Retired.
**Depends on:** S8, S11.

| ID | Task | Status |
|---|---|---|
| S12.1 | Suggestion sources: scan match with a different company or email domain (moved), bounce flag on an email (bounce), manual mark | [x] |
| S12.2 | Career moves screen: pending suggestions, recent changes, filters | [x] |
| S12.3 | Possible job change: "Add as new role, keep history" (default), "Replace old details", "Different person"; keep old email as former; set a replacement at the old company | [x] |
| S12.4 | Role history on detail: timeline of roles with dates and source | [x] |
| S12.5 | Mark retired: role and person status retired, prompt for replacement | [x] |
| S12.6 | Successions: predecessor, successor, company, role title, date, source, note | [x] |
| S12.7 | "Replaced by" card on the predecessor (call/email buttons), "Replaces" on the successor | [x] |
| S12.8 | Move open follow-ups to the successor in one tap | [x] |
| S12.9 | "Check on web" with "retirement" added for retired checks; result recorded by hand | [x] |
| S12.10 | Per-person `track_career` and a global switch in Settings | [x] |
| S12.11 | Former and bounced contact points never used as the default target | [x] |
| S12.12 | Replacement chains: one level per succession row, UI shows the latest (spec open item) | [x] |

**Tests:** every resolve option end-to-end on the database; succession display; follow-up transfer.

---

## M5 Data in and out (0.5.0)

### S13 Import, export, backup, My card

**Goal:** your data is never stuck in the app. Mockups: Import, Export, MyCard.
**Depends on:** S8, S9, S10.

| ID | Task | Status |
|---|---|---|
| S13.1 | Export formats: vCard 3.0 (default), 4.0, CSV generic, HubSpot, Salesforce | [x] |
| S13.2 | Export scope: everyone, a tag, an event, a selection; options: include images, include notes | [x] |
| S13.3 | Export destination: share sheet or save to a chosen folder (Storage Access Framework) | [x] |
| S13.4 | Import .vcf (single and multi-contact files); opened from other apps too (intent filter for text/vcard) | [x] |
| S13.5 | Import CSV with a column-mapping screen, preview of 5 rows, saved mappings | [x] |
| S13.6 | Import phone contacts (READ_CONTACTS, optional, read once, not kept in sync) | [ ] later (needs READ_CONTACTS) |
| S13.7 | Every import row: Imported tag, then the duplicate/job-change match from S8/S12; summary (new, merged, skipped) | [x] |
| S13.8 | Backup: zip of the SQLite file + images + manifest (schema version, app version, counts, sha256 per file) | [x] |
| S13.9 | Restore: checks manifest version, refuses newer schema, migrates older, confirms before replacing, keeps the previous database as a fallback copy | [x] |
| S13.10 | Weekly auto-backup to a folder you choose, run when the app is opened and a backup is due (no background service), keep last N | [~] weekly, on the phone (keeps 4), each can be saved or shared; a chosen folder needs persistent SAF access |
| S13.11 | My card: your own details, QR of your vCard (full screen, max brightness), share as .vcf | [x] |
| S13.12 | My card: write to a blank NTAG215/216 (v1.x, from S14; lock is a separate confirm) | [ ] |

**Tests:** export golden files per format, import of 10 real-world vCard files (Google, Outlook, iPhone, LinkedIn) and 3 CSVs, backup then restore round-trip with images.

---

## M6 Tap cards (0.6.0)

### S14 NFC tap cards

**Goal:** read NFC business cards. Mockup: TapCard.
**Depends on:** S7, S8.

| ID | Task | Status |
|---|---|---|
| S14.1 | `nfc_manager` 4.x + `nfc_manager_ndef`; `checkAvailability()` first; `stopSession()` on leave | [ ] |
| S14.2 | States: idle, listening, tag found, reading, parsed (vcard, link, text, empty, unsupported), tag lost; NFC off, no NFC hardware | [ ] |
| S14.3 | Android reader mode loop with counter and haptic per card; 3 s debounce per tag | [ ] |
| S14.4 | iOS: one tap per session, "Tap next" button, capability + usage string + entitlement | [ ] |
| S14.5 | NDEF parser (pure Dart): MIME vCard, URI with prefix codes (0x01 to 0x06), Smart Poster, Text, MECARD/vCard inside text, multiple records | [ ] |
| S14.6 | Link cards: open in default browser (default), save link only (website + "NFC link" tag), app registered as .vcf handler so "Add to contacts" lands in Review | [ ] |
| S14.7 | Optional "Fetch details from link cards" (off by default): https only, 10 s timeout, 1 MB cap, 3 redirects, no cookies; ask first per domain; looks for vCard link, .vcf href, ld+json Person, Open Graph | [ ] |
| S14.8 | Security: hostile payloads, size caps, control characters stripped, no HTML rendering, no reading of payment or access badges | [ ] |
| S14.9 | Dedupe: tag UID + NDEF hash; URL normalisation drops counter/MAC parameters (ctr, cmac, sig, e, c) for rolling-URL cards | [ ] |
| S14.10 | Event inheritance and the same duplicate/job-change match as photo scans | [ ] |
| S14.11 | Tap + photo of the same card merge into one record | [ ] |
| S14.12 | "Keep raw tag data" setting (off: raw payload dropped after parsing) | [ ] |
| S14.13 | Antenna tip per platform; NFC-off deep link to settings | [ ] |
| S14.14 | Write your own tag from My card (v1.x) | [ ] |

**Tests:** NDEF byte fixtures for every record type; fuzz tests (oversized fields, bad length bytes, control characters).
**Emulator check:** UI states only (the emulator has no NFC). NFC reading is entirely a phone-test item.

### M6 release

Phone test sheet 0.6.0: your 3 to 5 real tap cards (vCard, URL, any rolling-URL card), NFC off state, tap at an event, re-tap the same card.

---

## M7 Lock-down (0.7.0)

### S15 Settings, security, onboarding, states

**Goal:** private by default and finished around the edges. Mockups: Settings, Onboarding, States.
**Depends on:** S4 to start, S14 to finish.

| ID | Task | Status |
|---|---|---|
| S15.1 | Settings screen: search engine for web checks (Google, DuckDuckGo, Bing), default region, digest time, auto-save clean cards, career tracking global switch, keep raw tag data, fetch details from link cards, backup folder and schedule, purge window, export defaults | [ ] |
| S15.2 | App lock: biometric or device passcode (`local_auth`), lock after N minutes in background, lock on start | [ ] |
| S15.3 | FLAG_SECURE on locked state and app switcher preview (Android), privacy blur on iOS | [ ] |
| S15.4 | Encrypted database: SQLCipher with the key in Android Keystore / iOS Keychain [?] see decision D3 | [ ] |
| S15.5 | Migration of an existing plain database to encrypted on first enable, with a backup first | [ ] |
| S15.6 | "Smart parsing (AI)" toggle: off by default; if ever built, shows exactly what leaves the device [?] decision D5 | [ ] |
| S15.7 | Delete everything (typed confirmation), per-person delete with purge after sync | [ ] |
| S15.8 | Welcome / onboarding: what the app does, privacy promise (no account, no cloud), camera and notification permission primers, import offer | [ ] |
| S15.9 | Empty states for every list (no contacts, no events, empty queue, no follow-ups, no duplicates, no tags) with one clear action each | [ ] |
| S15.10 | Error states: camera denied, NFC off, no NFC, storage full, restore failed, import errors with row numbers | [ ] |
| S15.11 | About: version, licences (`showLicensePage`), privacy policy link (default browser), changelog | [ ] |
| S15.12 | No analytics, no telemetry, no crash reporting service; network permission justified only by link fetch and LAN sync | [ ] |

**Tests:** settings persistence, lock timing with a fake clock, encryption round-trip and wrong-key failure.

---

## M8 Desktop (0.8.0)

### S16 Sync and Windows desktop

**Goal:** the same library on your PC, over your own network. Mockup: Sync.
**Depends on:** S15 (all tables final).

| ID | Task | Status |
|---|---|---|
| S16.1 | Change tracking: `updated_at` on every row, tombstones, per-device last-sync watermark | [ ] |
| S16.2 | Pairing QR: `{host, port, token, cert_sha256, device_name, v}`; token one-time, expires in 2 minutes | [ ] |
| S16.3 | Host: HTTPS server on the LAN only while the Sync screen is open; self-signed cert generated per device; client pins the fingerprint from the QR | [ ] |
| S16.4 | Endpoints: POST /pair, GET /changes?since=, POST /changes, GET /blob/{sha256}, PUT /blob/{sha256} | [ ] |
| S16.5 | Merge: last-write-wins per record by `updated_at`, clock offset measured at pair time; same-field edits on both sides inside the window go to a conflict list | [ ] |
| S16.6 | Conflict list screen: pick a side per field | [ ] |
| S16.7 | Images sync by hash, only missing ones; resumable | [ ] |
| S16.8 | Phone hosts first (suits locked-down work laptops), then desktop hosts | [ ] |
| S16.9 | Devices table: paired devices, last sync, unpair | [ ] |
| S16.10 | Fallbacks: phone hotspot, backup zip import | [ ] |
| S16.11 | Windows build: window size/state memory, keyboard shortcuts (Ctrl+F search, Ctrl+N new), wider two-pane layout (list + detail), drag-and-drop of card images and .vcf files | [ ] |
| S16.12 | Windows: card import from folder or webcam; optional USB NFC reader (ACR122U via PC/SC) is v1.x | [ ] |
| S16.13 | Windows packaging: MSIX or zip, built by CI on tag | [ ] |
| S16.14 | Windows Firewall prompt handling and copy for the host side | [ ] |

**Tests:** sync engine tests with two in-memory databases (inserts, edits, deletes, conflicts, clock skew, interrupted transfer); pairing token expiry; cert pin mismatch rejected.
**Emulator check:** emulator as phone + Windows build on this PC on the same host network.

---

## M9 Release (1.0.0)

### S17 Release 1.0

**Goal:** on Google Play, documented, audited.
**Depends on:** everything.

| ID | Task | Status |
|---|---|---|
| S17.1 | `/mobile-audit` release audit (MASVS, privacy, permissions, store compliance) and fixes until Go | [ ] |
| S17.2 | `/prerelease-audit` full pass (GUI controls, engine, data safety, packaging, docs truth) | [ ] |
| S17.3 | Performance pass on your phone: cold start, 5,000 contacts, batch scanning speed | [ ] |
| S17.4 | Accessibility pass: TalkBack walk-through, 200% font, contrast | [ ] |
| S17.5 | App icon, adaptive icon, feature graphic, splash (final artwork) | [ ] |
| S17.6 | Privacy policy on GitHub Pages | [ ] |
| S17.7 | Data Safety form: camera, optional contacts, no data collected or shared, network only for local sync and optional link fetch | [ ] |
| S17.8 | Store listing: short and full description, 4+ light-theme screenshots from the seeded demo database | [ ] |
| S17.9 | Play App Signing, AAB build in CI, `play` flavour without self-update code | [ ] |
| S17.10 | Closed test (new personal accounts need testers for a set period before production) [?] decision D7 | [ ] |
| S17.11 | Production release | [ ] |
| S17.12 | Major-release documentation set into `Documentation/`: User Manual, Install Manual, Release Notes, README, Package Overview (simple / medium / advanced), as PDF and Word, `Rev 1.0` | [ ] |
| S17.13 | GitHub repo details: description, topics, README screenshots from the 1.0 build | [ ] |
| S17.14 | iOS: build and test on an iPhone if you want iOS in 1.0 [?] decision D2 | [ ] |

---

## Cross-cutting rules (apply to every section)

| Area | Rule |
|---|---|
| Privacy | Nothing leaves the device except LAN sync and the opt-in link fetch. No analytics. On-device OCR only. EXIF stripped. |
| Links | Every web, tel, sms, mailto and maps link opens in the default app via `url_launcher` external mode. No in-app web view. |
| Data safety | Never hard-delete outside the purge job. Write the capture to disk before processing. Back up before migrations and restores. |
| Wording | Use the full word "cumulative" in reports. Plain labels, no jargon on screen. |
| Navigation | Side drawer only. No bottom tabs. |
| Theme | Light theme, tokens from S3.1, Newsreader + Hanken Grotesk. |
| Tests | Every section adds unit/widget tests; `flutter analyze` clean; parser and sync logic are pure Dart and tested without a device. |
| Emulator | Each section ends with an emulator check and screenshots before the commit. |
| Phone | Phone testing happens at milestone releases only, from the GitHub Release APK, using the phone test sheet. |
| Commits | Authored as AxialForge, imperative mood, no prefixes, no attribution trailers. One section can be several commits. |
| Releases | Version only in `pubspec.yaml`; CHANGELOG in the same commit; tag `vX.Y.Z`; CI builds and attaches APKs. |
| Docs | Finished PDFs and Word files go in `Documentation/` as `<name> Rev x.y`, portrait only. |
| Gotchas | Anything that costs real debugging time goes into the Gotchas section of `CLAUDE.md`. |

## Decisions needed from you

| ID | Question | Needed by | Suggested answer |
|---|---|---|---|
| D1 | App name and app id (`com.axialforge.card_organizer`), final before the first Play upload | S0 / S17 | Keep "Card Organizer" for now |
| D2 | iOS in 1.0, or Android + Windows first and iOS later | S17 | Android + Windows first |
| D3 | Encrypted database: SQLCipher (drift's `sqlcipher_flutter_libs` is now marked end-of-life, so a replacement setup is needed) or app lock only | S15 | Decide at S15 after checking the current drift encryption route |
| D4 | Camera package | S5 | Decided: `camera` (official) |
| D5 | "Smart parsing (AI)" at all | S15 | Leave out of 1.0 |
| D6 | GitHub repo public or private, and licence | S0 / S17 | Private until 1.0 |
| D7 | Play closed test: who are the testers | S17 | Plan early; the waiting period is the longest single step |
| D8 | Purge window for tombstones (30 days?) | S1 | 30 days |
| D9 | Which follow-up email template text you want | S11 | Draft one at S11 |

## What I need from you, by milestone

| When | What |
|---|---|
| Now (S2) | 10 to 20 real card photos to start, 40 in the end, including dark, glossy, vertical, two-sided and non-English cards |
| M1 | Phone test of 0.1.0 and whether ML Kit gives line confidence on your phone |
| M2 | Phone test of scanning in real light conditions |
| M6 | 3 to 5 real NFC tap cards, and what a generic NFC reader app shows when you scan them |
| M8 | Your Windows PC on the same network as the phone for the sync test |
| M9 | Testers for the Play closed test, store listing text review |
