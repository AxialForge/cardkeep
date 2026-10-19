# Card Organizer, Spec v0.2

Flutter (Android/iOS first, Windows/macOS later). Local-first. No account, no cloud, no background services.
Supersedes v0.1. UI reference: the "Card Organizer UI, Executive" canvas (24 screens).

## 1. What changed since v0.1
- Events (trade shows, networking) with goals, scan sessions, per-event follow-up tracking and export
- Career tracking: job changes, retirement, replacement person
- Lead rating (hot/warm/cold), follow-up notifications, QR-on-card detection
- My card (share your own vCard QR), CRM-ready CSV exports, app lock + encrypted DB
- Import (vCard, CSV, phone contacts), Duplicates/Merge, Tags, Settings, onboarding, empty/error states

## 2. Screens (all in canvas)
Contacts, Contact detail, Edit contact, Menu, Scan, Review scan, Review queue, Events, Event detail, New event,
Career moves, Possible job change, Retired contact, Follow-ups, Duplicates, Merge, Tags, Import, Export and backup,
Sync to desktop, My card, Settings, Welcome, Empty/error states.
Nav: side drawer only, no bottom tabs (per your design conventions).

## 3. Data model (drift / SQLite)
Every table: `uuid TEXT PK, created_at, updated_at, deleted_at NULL` (tombstone for sync).

```
people        (uuid, first, last, display_name, lead_rating[hot|warm|cold|null], track_career BOOL,
               status[active|moved|retired|unknown], notes, met_event_id NULL, introduced_by_person_id NULL,
               followup_at NULL, followup_done_at NULL)
companies     (uuid, name, name_norm, domain NULL, website NULL, address NULL)
roles         (uuid, person_id, company_id, title, start_date NULL, end_date NULL,
               status[current|former|retired], source[scan|manual|import|web_check|bounce],
               source_card_id NULL, confirmed_at)
contact_points(uuid, person_id, role_id NULL, kind[mobile|office|email|web|address], value, label,
               is_primary, status[active|former|bounced])
successions   (uuid, company_id, role_title, predecessor_person_id, successor_person_id NULL,
               effective_date NULL, source, note)
change_suggestions(uuid, person_id, kind[moved|retired|bounce], payload_json,
               status[pending|applied|dismissed], source[scan|bounce|manual], created_at)
cards         (uuid, person_id NULL, front_sha256, back_sha256 NULL, ocr_json, scan_session_id NULL,
               status[parsed|needs_review|saved], scanned_at)
events        (uuid, name, type[trade_show|networking], start_date, end_date, location, booth NULL,
               goal INT NULL, notes, auto_scan BOOL, reminder_offset_days)
scan_sessions (uuid, event_id NULL, started_at, ended_at NULL)
tags          (uuid, name, color)      person_tags (person_id, tag_id)
devices       (uuid, name, platform, cert_fingerprint, last_sync_at)   -- sync pairing
```
Images are files on disk named by sha256; DB stores the hash only. Event stats (cards, contacts, companies, follow-ups sent) are queries, not stored columns.

## 4. Career tracking
Goal: know when someone changed companies or retired, keep the history, and surface the replacement with their card.

**Sources (no scraping, no background jobs):**
1. New scan matches an existing person, different company or email domain: create a `moved` suggestion.
2. You flag an email as bounced: `bounce` suggestion.
3. You mark someone retired or moved by hand.
4. "Check on web" opens a search in the default browser. You record what you find. The app never fetches pages itself.

**Match rule on save (in order):** exact mobile number; normalized name + same email local part; normalized name + fuzzy company/domain (Jaro-Winkler >= 0.9). A match with the same company is a duplicate (Merge). A match with a different company is a job change.

**Resolve options (Possible job change screen):**
- Add as new role, keep history (default): old role gets `status=former`, `end_date`=scan date; new role `current`.
- Replace old details (no history).
- Different person (dismiss).
- Optional: keep old email as `former`; set a replacement at the old company.

**Retirement and replacement:**
- Mark retired: role `status=retired`, person `status=retired`, prompt for a replacement.
- Replacement is a `successions` row: predecessor, successor person, company, role title.
- Predecessor screen shows "Replaced by" with the successor's card, phone, email (call/email buttons). Successor screen shows "Replaces".
- Open follow-ups can be moved to the successor in one tap.
- If a mover leaves a company, the same prompt asks who took over (optional).

**Rules:** old phones/emails are kept but marked `former`/`bounced` and never used as the default call/email target. Tracking is per person (`track_career`) and globally switchable in Settings.

## 5. Links and default browser
- Use `url_launcher` with `launchUrl(uri, mode: LaunchMode.externalApplication)` for all web links, tel:, sms:, mailto:, and maps.
- Web links open in the phone's default browser. No in-app web view.
- Settings has a "Search engine for web checks" value (Google, DuckDuckGo, Bing). It only changes the search URL template, for example `https://www.google.com/search?q={query}`.
- Android 11+: declare `<queries>` intents for https, tel, mailto, sms in the manifest. iOS: add the schemes to `LSApplicationQueriesSchemes` only if `canLaunchUrl` is used.
- Query = "{first} {last} {company}" (URL-encoded). Add "retirement" for retired checks.

## 6. Scan and parse
Pipeline: capture (edges, crop, perspective, glare/blur check) -> QR check first (vCard/MECARD QR beats OCR) -> ML Kit OCR with boxes -> parse -> review -> save -> match (duplicate or job change).

Parser rules (run in order, each field gets a confidence 0..1):
1. Email: regex, lowercase. Website: domain regex, drop if it equals the email domain only when no other URL.
2. Phones: libphonenumber, region from device locale. Label by nearby token (M, Mobile, Cell, O, Office, T, Tel, F, Fax). Fax is dropped to notes.
3. Address: postal-code regex (US ZIP / CA / UK / EU) plus the 1 to 2 lines above it.
4. Title: match against a keyword list (Director, VP, Manager, Engineer, President, Chief, Head of, Sales, Buyer, Procurement...). Keep the whole line.
5. Name: highest font-height line that is not company/title/contact; 2 to 4 capitalized tokens; strip credentials (PE, MBA, PhD) into a suffix.
6. Company: logo-adjacent line, or domain-derived name when the OCR line is ambiguous; legal suffix kept (Inc, LLC, Corp, GmbH).
7. Anything unassigned goes to notes. Confidence < 0.7 is flagged amber on the review screen.

Batch mode: capture continues while OCR runs on a worker isolate; clean cards auto-save, flagged ones go to the Review queue.


## 6b. NFC tap cards
- Phones read NFC (13.56 MHz) only. Most tap business cards are NTAG213/215/216 with NDEF data. Cards on 125 kHz RFID cannot be read by a phone. Desktop can use a USB PC/SC reader (ACR122U class) later.
- Package: `nfc_manager` (Android + iOS). iOS needs the NFC capability, `NFCReaderUsageDescription`, and reads only while the Tap screen is open. Android needs `android.permission.NFC` (no runtime prompt).
- NDEF records and handling:
  1. MIME `text/vcard` or `text/x-vcard`: parse with the vCard reader, go straight to Review. Works offline.
  2. URI record (most common, e.g. a profile page): store as the person's website, mark `source=nfc_link`. Default action: "Open in browser" (default browser). "Save link only" creates a contact with the link.
  3. Optional "Fetch details from link cards" (Settings, off by default): HTTP GET the page, read its vCard link, `application/ld+json` Person, or `.vcf` href. This is the only network use in the app and it must be visible in the UI.
  4. Empty, locked, or non-NDEF tag: show the error state, offer Retake via camera.
- Tapped cards use the same event/scan-session inheritance, duplicate match, and job-change match as photo scans.
- Dedupe by tag UID plus NDEF hash so re-tapping the same card does nothing.
- Raw tag data is discarded unless "Keep raw tag data" is on.
- Test set: 10 real tap cards (vCard, URL, mixed, empty) added to section 12.

## 7. Events
- Fields: name, type, dates, location, booth/table, contact goal, notes, auto-start scan session, reminder offset.
- Scan session: set the event once, every card scanned inherits it. With auto-start on, the session opens on the first event day.
- Event screen shows cards, contacts, companies, goal progress, follow-ups sent vs due. Actions: draft follow-ups for the rest, export event contacts (vCard/CSV).
- Past events keep their contacts. A contact's "Met at" links back to the event.

## 8. Follow-ups and reminders
- One `followup_at` per person (v1). Local notifications via `flutter_local_notifications`, scheduled at the due date, 8:00 local, or the daily digest time.
- Event reminders: `end_date + reminder_offset_days` applied to every contact from the event.
- Follow-ups list groups: Overdue, This week, Later. Done sets `followup_done_at`.

## 9. Export, import, backup
- vCard 3.0 (default), 4.0, CSV generic, CSV HubSpot columns, CSV Salesforce columns. Scope: everyone, a tag, an event. Optional images and notes.
- Import: .vcf, CSV with column mapping, phone contacts (read once, not kept in sync). Imported rows get an Imported tag and go through the same duplicate match.
- Backup: zip of the SQLite file + images + a manifest (schema version). Restore checks the version. Optional weekly auto-backup to a user-chosen folder.

## 10. Sync (phone <-> desktop)
- QR payload: `{host, port, token, cert_sha256, device_name, v}`. Token is one-time, expires in 2 minutes.
- Host runs an HTTPS server on the LAN only while the Sync screen is open. Client pins the cert fingerprint from the QR.
- Either side can host. Phone hosts and desktop connects out suits locked-down work laptops.
- Endpoints: `POST /pair`, `GET /changes?since=<ts>`, `POST /changes`, `GET /blob/<sha256>`, `PUT /blob/<sha256>`.
- Merge: last-write-wins per record by `updated_at` (device clocks compared at pair time and corrected). Same-field edits on both sides inside the window go to a conflict list.
- Deletes are tombstones. Images sync by hash, only the missing ones.
- Fallbacks: phone hotspot, or backup zip import.
- Not Bluetooth: too slow for images and restricted on iOS.

## 11. Security and privacy
- SQLCipher-encrypted DB, key in Android Keystore / iOS Keychain. App lock with biometric or device passcode.
- On-device OCR only. "Smart parsing (AI)" is off by default and, when on, must show exactly what leaves the device.
- No analytics, no telemetry, no accounts. Career tracking never contacts a third party by itself.
- Personal data about other people: provide "Delete everything" and per-person delete (tombstone, then purge after sync).

## 12. OCR test set (build this first)
- 40 real cards: 10 plain, 8 dark/colored, 6 glossy (glare), 6 vertical, 5 two-sided, 5 non-English accents or two-language.
- Ground truth in `test/cards/<id>.json` (fields) next to the image.
- Metric: per-field exact match after normalization. Targets: email/phone >= 98%, name >= 92%, company >= 90%, title >= 85%.
- Run in CI on every parser change. Parser is pure Dart, so it tests without a device.

## 13. Repo layout
```
lib/
  core/        db (drift), models, sync, vcard, csv, link_launcher
  features/    scan, review, contacts, events, career, followups, duplicates, tags, import_export, sync, settings
  parser/      qr, ocr_adapter, rules, match
test/          parser/, match/, vcard/, sync/, cards/ (ground truth)
```
CI (Gitea Actions): `flutter analyze`, `flutter test`, build APK on tag.

## 14. Build order
1. Drift schema + migrations, vCard/CSV writers (tests first)
2. Parser + OCR adapter against the 40-card set
3. Contacts list, detail, edit, tap-to-call/mail/web
4. Scan, review, queue, batch
5. Duplicates + merge
6. Events + scan sessions + follow-ups + notifications
7. Career tracking (suggestions, roles, successions)
8. Import/export/backup
9. Settings, app lock, encryption
10. Sync (phone hosts first, then desktop client)
11. Desktop build (Windows first)
12. Release

## 15. Release checklist (Google Play, individual account)
- Privacy policy hosted on GitHub Pages (no website needed)
- Data Safety form: camera, optional contacts access, no data collected or shared, no network use except local sync
- Permissions declared: CAMERA, POST_NOTIFICATIONS, READ_CONTACTS (optional)
- App icon, feature graphic, 4+ light-theme screenshots, short and full description
- Closed test run per Play's requirements for new personal accounts before production

## 16. Open items
- Replacement chains (A replaced B who replaced C): v1 stores one level per succession row, UI shows the latest.
- Multi-role people (board seats, two employers): v1.x.
- Email-bounce detection is manual. Reading a mailbox is out of scope.
