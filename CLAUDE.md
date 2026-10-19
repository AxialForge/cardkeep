# Card Organizer — project brief for Claude Code

Local-first business card organizer. Flutter (Android + iOS first; Windows/macOS later). No accounts, no cloud, no background services.

## Read first
1. docs/card-organizer-spec-v0.2.md — full spec (screens, drift data model, career tracking, links, scan/parse, NFC, events, follow-ups, export/import, sync, security, OCR test set, repo layout, build order, Play release checklist, open items)
2. docs/card-organizer-scanning-deep-dive.md — photo scanner, QR, NFC detail
3. design/executive/ — 25 phone-size mockups (`*.dc.html`, open in a browser; `canvas.json` lists boards and layout). Sample data is fictional.

## Stack
Flutter, drift/SQLite, google_mlkit_text_recognition + barcode scanning, opencv_dart (quad detect / warp), nfc_manager (+ nfc_manager_ndef), url_launcher (externalApplication), QR-pair local sync (pinned TLS, one-time token).

## Design rules
- Side drawer only. No bottom tabs. Flat drawer.
- Light theme. Tokens: ground #F3F4F6, surface #FFFFFF, ink #0E1A2B, ink2 #4A5568, hairline #E2E5EA, brass #B08A4A (text #7A5B22), amber #FBF1DC/#7A4E0B, Hot #F8E1DD/#8C2F1F, Cold #E1EAF5/#1F4A78.
- Fonts: Newsreader (display), Hanken Grotesk (UI).
- All web links open in the default browser. Use the full word "cumulative" in reports.

## Build order
Follow section "Build order" in the spec: data model + contacts list, then scanner/parser/review, QR + export/backup, events/follow-ups/duplicates, career tracking, NFC, desktop + sync, release.

## Unverified
Nothing is built or device-tested. ML Kit Flutter per-line confidence is unconfirmed. Scan thresholds (blur 80, glare 1.5%, 45% frame, 1400 px) are starting values to tune with real card photos and tap cards.

## Folders
- docs/ specs
- design/executive/ final mockups; design/v1-basic/ earlier simpler version; design/tools/gen_screens.py generator for most screens
- deck/ source for the overview deck (deck.json + slides/*.html)

## Gotchas
- Don't edit source with PowerShell `Get-Content`/`Set-Content`: 5.1 reads BOM-less UTF-8 as ANSI and writes mojibake into regexes (é, –, ’). Use the Edit tool or Python with `encoding='utf-8'`.
- drift copies `clientDefault` closures into `database.g.dart`, so helpers they call must be public (`uuidGen`).
- Phones are stored E.164 (`+13305550101`); the duplicate match compares them exactly. Format only for display.
- ML Kit runs on Android/iOS only, so `.ocr.json` fixtures must be captured on a phone; the parser itself is pure Dart.
