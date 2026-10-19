# Card Organizer: Scanning Deep Dive (photo, QR, NFC)

Companion to spec v0.2 (sections 6, 6b, 12). Threshold numbers are starting values to tune on the real-card test set.
Package facts were checked against pub.dev and ML Kit docs on Oct 19, 2026. Re-check versions before you pin them.

## 0. Decisions in one screen
- **One pipeline, three sources.** QR code, NFC tag, and photo OCR all produce the same `CardCandidate`. They merge, then go to Review, duplicate match, and job-change match.
- **Photo OCR:** Google ML Kit text recognition on-device, behind an `OcrEngine` interface so Apple Vision or Tesseract can be swapped in.
- **Card detection:** write your own for cross-platform control (OpenCV quad detection). ML Kit Document Scanner is Android-only (community plugin, beta), so use it only as an Android shortcut if you want one.
- **NFC:** `nfc_manager` 4.x (Android + iOS) with the separate `nfc_manager_ndef` package. Phones read NFC (13.56 MHz) tap cards. Not 125 kHz RFID.
- **Link cards (URL only) are the common case.** Default is open in the default browser, user taps "Add to contacts", app receives the `.vcf`. No scraping needed.
- **Nothing leaves the device** unless the user turns on "Fetch details from link cards".

## 1. Unified model
```
CardCandidate {
  source: qr | nfc_vcard | nfc_link | ocr,
  fields: { name, title, company, phones[], emails[], urls[], address, notes },
  per-field confidence 0..1,
  images: { original, rectified } | null,
  raw: string | null            // QR/NFC payload, kept only if "Keep raw tag data" is on
}
```
Merge order per field: structured source (QR/NFC vCard) wins, OCR fills gaps, and a disagreement is flagged amber for Review.
A tapped card with a photo of its face is allowed: the NFC data is the contact, the photo is just the card image.

## 2. Photo scanner

### 2.1 Capture and quality gates
- Preview at 1080p, still capture at max resolution (12 MP is plenty). Tap-to-focus, continuous autofocus, torch toggle, exposure lock on first detection.
- Auto-capture fires when: card quad found, steady for about 400 ms (frame-difference or gyro below threshold), sharp, no glare. Manual shutter always works.
- Live hints, one at a time, in this priority: "Move closer", "Hold steady", "Glare, tilt the card", "More light", "Card cut off".

| Gate | Test | Start value |
|---|---|---|
| Card size | quad area / frame area | >= 45% |
| Sharpness | variance of Laplacian on card region, 1000 px long edge | >= 80 |
| Glare | blob of luminance >= 250 covering text area | < 1.5% of card area |
| Exposure | mean luminance of card region | 70 to 200 (of 255) |
| Resolution | rectified long edge | >= 1400 px (about 400 dpi for a 3.5 in card) |
| Skew | angle off the card's aspect ratio after rectify | < 5% error |

A failed gate on the saved still never blocks the capture. It sets a flag and the card goes to the Review queue with a reason chip ("Blurry", "Glare").

### 2.2 Card detection and rectification
Pipeline (OpenCV via `opencv_dart`, in a worker isolate):
1. Downscale to 640 px, grayscale, blur, Canny edges, close gaps.
2. Find contours, approximate to polygons, keep 4-point convex quads in the size range.
3. Score quads by aspect ratio: US 1.75, EU about 1.545, Japan about 1.65, also accept the rotated (portrait) versions. Reject anything far from these.
4. Warp perspective to a flat rectangle at the target size. Use the aspect ratio of the best match.
5. Fallback when no quad is found (dark card on dark table, white card on white paper): offer a manual 4-corner crop with magnifier handles.
- Orientation: after OCR, use ML Kit block angles to rotate upright (portrait cards, upside-down shots).
- Android shortcut: `google_mlkit_document_scanner` gives cropping and perspective with Google's own UI, but it is Android-only, depends on Play services, and the flow is fixed. Fine for a v0 spike, not for a shared batch UI.
- iOS shortcut: VisionKit document camera. Same trade-off.

### 2.3 Preprocessing for OCR
- Always run OCR on the rectified image.
- Pass 1: as-is. If mean text confidence < 0.8 or the card is dark: pass 2 on a contrast-enhanced copy (CLAHE) and, for dark backgrounds, an inverted copy. Keep the pass with the higher confidence per line.
- Never binarize hard. Foil and embossed text fall apart.
- Cap OCR input at about 2000 px long edge. More pixels are slower, not better.

### 2.4 OCR engine
- ML Kit Text Recognition v2, on-device. Scripts: Latin (default), Chinese, Devanagari, Japanese, Korean.
- The native API returns a bounding box, corner points, and confidence per block, line, element, and symbol. The Flutter plugin docs list boxes and corner points but do not mention confidence. Check the plugin's `TextLine` fields on day one. If confidence is missing, derive it (section 2.7) or add a small platform channel.
- Non-Latin scripts need extra model dependencies on each platform. Bundle them if you want guaranteed offline use.
- Dual-language cards (English plus Japanese): run Latin plus the second script, merge lines by position.
- Platform minimums for the plugin: iOS 15.5+, Android minSdk 21.
- `OcrEngine { Future<OcrResult> read(Image img, List<Script> scripts); }` returns lines with text, box, angle, confidence. Parser code never imports ML Kit.

### 2.5 QR and barcode on the card
- ML Kit Barcode Scanning runs on the same preview frames, cheap and parallel.
- `contactInfo` (vCard or MECARD) goes to a structured `CardCandidate` and beats OCR.
- A URL QR is treated exactly like an NFC link card (section 3.6).
- Ignore QR codes whose payload is not a contact or URL (Wi-Fi, SMS, app store links) unless the user taps them.

### 2.6 Layout parsing (field scoring)
Group lines into blocks by proximity. Score every line for every field, then assign with a global pass so each single-value field is used once.

| Field | Signals (weighted) |
|---|---|
| Email | regex (certain). Lowercase. Multiple allowed. |
| Phone | libphonenumber parse + `isValid`. Label from nearby token: M, Mobile, Cell, C, O, Office, T, Tel, D, Direct, F, Fax. Fax goes to notes. Extensions: "x123", "ext. 123". |
| URL | domain regex, not equal to an email-only domain, strip "www". |
| Address | postal code pattern (ZIP, CA, UK, EU) plus the 1 to 2 lines above it; state/province tokens. |
| Title | keyword list match (Director, VP, Manager, Engineer, President, Chief, Head of, Buyer, Procurement, Sales...), title-case, 1 to 6 words. |
| Name | largest text height among lines not matched as other fields, 2 to 4 capitalized tokens, no digits, not all caps with a legal suffix, tokens appear in the email local part (strong boost). Credentials (PE, MBA, PhD, CPA) go to a suffix. |
| Company | line near the logo (top), legal suffix (Inc, LLC, Corp, Ltd, GmbH), all caps, similarity to the email/web domain (strong boost). Falls back to domain-derived name. |
| Tagline, slogan | unmatched italic or small lines go to notes. |

Cross-checks raise confidence: name tokens in the email, company text close to the domain, phone valid for the region.
Field confidence = 0.5 x OCR confidence + 0.3 x rule score + 0.2 x cross-check. Below 0.7 is flagged amber in Review.

### 2.7 Normalization
- Phones to E.164 internally, display in local format. Region from the event location, then device locale.
- Emails lowercased, trailing punctuation stripped. URLs get https and no tracking junk.
- Names: split first/last with Western and "Last, First" handling, suffixes stripped. Keep a display name exactly as printed.
- Company: store as printed plus a normalized key (case, punctuation, legal suffix removed) for matching "Halden Tooling Group" with "Halden Tooling".
- Address: single block, no splitting unless the postal parser is confident.
- Common OCR fixes: O/0, l/1/I in numbers and emails, "@" misreads, space inside emails, "rn" vs "m".

### 2.8 Two-sided and multi-language cards
- Back side is a second image linked to the same card record. Run the same pipeline, merge fields, flag conflicts.
- Back often holds the other language or an address. Store extra names as alternates: vCard 4.0 `ALTID`/`LANGUAGE`, vCard 3.0 `X-` properties.
- A handwritten back-side note is just an image the user can type a note against. No handwriting OCR in v1.

### 2.9 Multi-card shots (the pile)
- One frame can hold 2 to 6 cards on a table. Detect all quads, rectify each, run each through the pipeline, and show N results as a strip.
- Constraints: each card still needs >= 1400 px on its long edge, so 12 MP supports about 4 cards in frame. Warn when too small.
- Also: import from gallery, a PDF of scans, or a folder (desktop later: flatbed or webcam).
- This is the fastest way through a trade-show pile. Make it a Batch sub-mode.

### 2.10 Review screen behavior
- Image on top with colored boxes per assigned block. Tap a box to reassign it to a field. Tap empty text to create a block.
- Fields below with confidence dots. Amber fields first.
- Company and title autocomplete from existing contacts (so one company does not exist as 5 spellings).
- Email and phone fields use the right keyboard. Phone shows the parsed E.164 and any invalid-number warning.
- "Rescan region": pinch to zoom, run OCR on the crop.
- Save runs duplicate match and job-change match (spec section 4). A clean card with no match saves without extra taps.

### 2.11 Batch pipeline
```
captured -> rectifying -> ocr -> parsed -> {auto_saved | needs_review}
```
- Worker isolate, queue depth 8, drops to 1 on low memory.
- Auto-save when: name present, (phone or email) present, every required field confidence >= 0.85, no duplicate or job-change match, and "Auto-save clean cards" is on. Everything else goes to the Review queue.
- Queue screen shows counts by state and reasons ("Low confidence", "Possible duplicate", "Blurry", "Job change").
- Never lose a capture: write the original image to disk before any processing.

### 2.12 Storage and privacy
- Save original (JPEG q90), rectified (q85), thumbnail (400 px). Name by sha256 of the rectified image.
- Strip EXIF (including GPS) by default. The event already says where you met.
- Delete the temp frames after capture. Temp OCR text lives in memory only.
- OCR is on-device. Bundle ML Kit models if you need guaranteed offline behavior on Android.

### 2.13 Performance budgets (mid-range phone)
- Capture to Review shown: <= 2.5 s. OCR pass: <= 800 ms. Batch throughput: >= 20 cards/min. Peak memory <= 300 MB.

### 2.14 Failure modes
| Problem | What you do |
|---|---|
| Glossy glare | gate flag, ask to tilt; second pass uses the best of two frames |
| Dark card, light text | inverted pass |
| Script or decorative fonts | low confidence flag, Review shows crop |
| Foil/embossed text | contrast pass, manual field entry |
| Tiny type (< 6 pt) | resolution gate, rescan closer |
| Logo text read as name | name rule requires not-company-like and email token match |
| Vertical or rotated text | block angle rotation |
| Two cards overlapping | multi-card detector rejects; ask to separate |
| White card on white table | manual crop fallback |
| No card edges (cropped by phone case) | manual crop |

### 2.15 Test matrix (extends spec section 12)
- 40 real cards x 3 conditions (good light, dim, glare) = 120 images. Ground truth per card in JSON.
- Metrics per field: exact match after normalization. Targets: email/phone >= 98%, name >= 92%, company >= 90%, title >= 85%.
- Quad detection hit rate >= 97% on plain backgrounds, >= 90% on busy ones.
- Speed tests on a low-end Android and an older iPhone.

## 3. NFC tap cards

### 3.1 What can be read
| Tech | Phone can read | Typical use |
|---|---|---|
| NFC HF 13.56 MHz, ISO 14443A (NTAG213/215/216) | yes | tap business cards |
| NFC Forum Type 2/4/5 with NDEF | yes | tap business cards, smart posters |
| DESFire, MIFARE Classic (door badges) | UID only or locked | access badges: do not read |
| EMV payment cards | possible but never | not our job |
| LF 125 kHz RFID (EM4100, HID Prox) | no | old access cards |
| UHF RFID (860 to 960 MHz) | no | logistics tags |
Tag memory: NTAG213 144 bytes, NTAG215 504, NTAG216 888. A minimal vCard is about 150 to 300 bytes, so most vCard cards are 215/216. A URL fits anywhere. That is why URL cards dominate.

### 3.2 Platform behavior
**Android**
- `NfcAdapter` reader mode keeps listening while the Tap screen is open. Batch tapping is smooth: each tap adds a card and gives a haptic.
- Permission: `android.permission.NFC` in the manifest, no runtime prompt. User may have NFC switched off: detect and deep-link to NFC settings.
- Also register an `NDEF_DISCOVERED` intent filter if you want a tap to open the app from outside it (optional).
**iOS**
- Needs iPhone 7 or later, the NFC Tag Reading capability, an `NFCReaderUsageDescription` string, and the formats entitlement.
- Reading runs in a system-owned session, only while the app is in the foreground with the Tap screen open. Each session shows the system sheet and times out after about 60 s. You restart it per tap, so batch tapping is slower than Android. Say so in the UI.
- iPhone XS and later can also read some URL tags with the screen on and the app closed. That opens Safari or an app, not this app's flow. You do not control it.
**Both**
- Antenna position: iPhone top back, Android varies. Show a model-aware tip: "Touch the card to the top back of the phone, near the camera."
- Haptic and a short tick sound on a good read. Never auto-open anything.

### 3.3 Package and setup
- `nfc_manager` 4.2.1 (Android, iOS). Use its separate `nfc_manager_ndef` package for the cross-platform NDEF class.
- Always `checkAvailability()` first, `stopSession()` when leaving the screen.
- `Ndef.from(tag)` returns null for non-NDEF tags: show the "not a business card" state.
- Alternative for raw access (APDUs, Type 2 page reads): `flutter_nfc_kit`.

### 3.4 Tap state machine
```
idle -> listening -> tag_found -> reading -> parsed{vcard | link | text | empty | unsupported} -> review/save
                         \-> tag_lost (retry, "Hold the card still")
nfc_off | no_nfc_hardware | permission_denied -> explain + settings link
```
Debounce: ignore the same tag for 3 s after a good read.

### 3.5 NDEF parsing
Read all records in the message. Decide by type:
- **MIME `text/vcard` / `text/x-vcard`**: parse as vCard 2.1/3.0/4.0. Go to Review. Works offline.
- **URI record (well-known `U`)**: first byte is a prefix code. 0x01 `http://www.`, 0x02 `https://www.`, 0x03 `http://`, 0x04 `https://`, 0x05 `tel:`, 0x06 `mailto:`. Expand it. A `tel:` or `mailto:` becomes a phone or email field.
- **Smart Poster (`Sp`)**: contains a URI plus an optional title. Use the URI, keep the title as a note.
- **Text record (`T`)**: language byte plus text. Treat as a note, or a name if it is a single short line.
- **MECARD / `BEGIN:VCARD` inside text**: detect and parse.
- Multiple records: apply the above to each. A card may carry a vCard and a URL.
- Empty or locked tag: "This tag has no contact data."

### 3.6 Link cards (URL only)
Most tap cards (Popl, Linq, HiHello and similar services, plus DIY NTAG cards) store a profile URL. The tag has no contact fields. Options, in order:
1. **Open in browser** (default browser). The profile page usually has an "Add to contacts" button that downloads a `.vcf`.
2. Register the app as a handler for `.vcf` / `text/vcard` (Android intent filter, iOS document type). The download opens in the app and goes to Review. No scraping, no network from the app.
3. **Save link only**: create a contact with the website field and an "NFC link" tag. Fill details later.
4. **Fetch details from link cards** (Settings, off by default): the app requests the page itself and looks for, in order: `<link rel="alternate" type="text/vcard">`, an `<a href>` to a `.vcf`, `application/ld+json` with `@type: Person`, then Open Graph title. Rules:
   - https only, 10 s timeout, 1 MB cap, max 3 redirects, no cookies, generic user agent.
   - Show the domain and ask first the first time.
   - The tag owner can see the request. That is why it is off by default.
   - Page formats vary by service. Treat every result as low confidence and send it through Review.

### 3.7 Security
- Tags are writable by anyone unless locked. Treat every payload as hostile.
- Never auto-open a URL. Show the domain large, flag punycode, lookalike characters, and known shorteners before "Open".
- Sanitize vCard: max 8 KB from a tag, 1 MB from a file; field length caps; strip control characters; ignore embedded photos on tags; no HTML rendering of any field.
- Do not read or log payment or access-badge technologies. Ignore anything that is not NDEF.
- Raw tag data is dropped after parsing unless "Keep raw tag data" is on.

### 3.8 Dedupe
- Tag UID dedupes simple tags. Some secure cards (for example NTAG 424 DNA with rolling authentication) use a random UID and a changing URL parameter, so UID fails.
- Normalize URLs before comparing: lowercase host, drop query parameters that look like counters or MACs (`ctr`, `cmac`, `sig`, `e`, `c`).
- Final guard is the normal duplicate matcher on name, phone, email.

### 3.9 Tapping at an event
- Tap screen shows the active event chip. Every tapped card inherits it.
- Android: keep reading in a loop with a counter. iPhone: one tap per session, big "Tap next" button.
- A tap and a photo of the same person's printed card merge into one record (match on name + company/phone).

### 3.10 Writing your own tag (v1.x, optional)
- My card can write a vCard (or your profile URL) to a blank NTAG215/216 so you can hand out your own tap card.
- Write as NDEF MIME `text/vcard` under 480 bytes: name, title, company, one phone, one email. Offer "lock the tag" as a separate confirm because it cannot be undone.
- Both platforms can write NDEF. Test on Android first.

### 3.11 Desktop (USB readers)
- Windows (`winscard.dll`), macOS (`PCSC.framework`), Linux (`pcscd`) via FFI. Common readers: ACR122U, ACR1252U.
- NTAG over PC/SC (pseudo-APDUs): `FF CA 00 00 00` get UID; `FF B0 00 04 10` read 16 bytes from page 4. Page 3 holds the capability container (`E1 ...`). NDEF starts at page 4 as a TLV: `03 <length> <NDEF message> FE`. Then use the same NDEF parser as mobile.
- LF 125 kHz readers give a bare ID number, no contact data. Not supported.
- Desktop reader support is optional. Phone-to-desktop sync already covers it.

### 3.12 UX copy
- Idle: "Hold a tap card to the back of your phone."
- Link card: "This card holds a web link, not contact details."
- Empty: "This tag has no contact data. Try the camera instead."
- Off: "NFC is off. Turn it on in settings."
- iPhone: "Tap again for each card."

### 3.13 Tests
- 10 real tap cards: vCard, URL, smart poster, text, empty, locked, mixed, rolling-URL.
- Unit tests on NDEF byte fixtures for every record type (pure Dart, no device).
- Fuzz tests: oversized fields, control characters, malformed length bytes.

## 4. Packages to evaluate (check versions at pub.dev)
`camera` or `camerawesome`, `opencv_dart`, `image`, `google_mlkit_text_recognition`, `google_mlkit_barcode_scanning`, `google_mlkit_entity_extraction` (phone/email/URL/address cross-check), `google_mlkit_document_scanner` (Android only, optional), `phone_numbers_parser`, `nfc_manager` + `nfc_manager_ndef`, `flutter_nfc_kit` (raw access), `url_launcher`, `drift`.

## 5. What I need from you to finalize
1. 10 to 20 real cards (photos), including any dark/glossy ones, to fix field rules.
2. 3 to 5 real tap cards, and what the NFC reader app on your phone shows when you scan them (URL, vCard, or something else).
3. Android, iPhone, or both as your first test phone.
