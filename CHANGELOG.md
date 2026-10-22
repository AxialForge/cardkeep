# Changelog

All notable changes to CardKeep. Format: [Keep a Changelog](https://keepachangelog.com/), versions: [SemVer](https://semver.org/).

## [0.3.0] - 2026-10-21
### Added
- **Phone extensions** ("Ext. 112") are kept with the number and dialled after a pause; **fax numbers** are kept
  as their own line (shown and copied, never dialled).
- **Middle name or initial** on contacts ("Dana K. Reyes"), filled from the card.
- Names printed in capitals are re-cased ("FRED PANETO" -> "Fred Paneto", keeping McDonald, O'Brien and
  hyphens); titles too ("PLANT MANAGER" -> "Plant Manager", keeping VP, CEO and similar).
- **More from the card**: licence numbers, opening hours, social handles, "since 1985" and slogans are sorted into
  labelled lines instead of notes, and can be edited.
- **Company logo** cut from the card becomes the contact's picture (More -> Remove logo to undo).
- **Others at this company** on a contact's page.
- **+ menu** on Contacts: Scan a card, Scan a stack, Add by hand, Import card photos.
- Sort names by **first or last name** (Settings, or the switch under the sort control).
- **Lead ratings can be switched off** (Settings, or the menu on the edit page); they disappear everywhere.
- Themes: **Navy and brass dark** added; Medium removed (it was too close to Light; it now shows as Light).

### Fixed
- Card reading: "1" read as "I" and "0" as "O" inside phone numbers is corrected, so numbers and extensions
  are no longer dropped; addresses with a spelled-out state ("Eastlake, Ohio 44095") are read in full; a label
  left on its own ("E-Mail") no longer ends up in notes.
- **Events** (drawer): trade shows and networking events with dates, location, booth, a contact goal and notes.
  **Start scanning for this event** opens a scan session: every card scanned goes with the event (shown on the
  scanner), and contacts saved from those cards are marked "Met at" it. An event page shows the goal ring, cards,
  contacts, companies and follow-ups, and who you met. Events set to auto-start open their session the first time
  you open CardKeep on an event day.

## [0.2.2] - 2026-10-20
### Fixed
- Scanning on a phone: the release build couldn't read text or QR codes (Android's code shrinker removed parts of
  the on-device reader), so the scanner captured, showed "Reading card..." and started over. Cards are read again.
- If reading a card ever fails, the card is kept (fill it in by hand) and the scanner says so instead of looping.

## [0.2.1] - 2026-10-20
### Added
- **Tags** (drawer): your own groups with a name and colour. Add them on a contact's page, or select several
  contacts and tap the tag button. Tags appear as filters on Contacts and are searchable. Deleting a tag asks first
  and says how many people have it; the contacts stay.
- **Duplicates** (drawer): people who look like the same person (same mobile, or the same name with the same
  email or company), each with the reason. **Compare and merge** picks the name, title and rating per field and
  combines phones, emails, cards, tags and notes; **Undo merge** works until CardKeep closes. "Not the same person"
  is remembered. A contact's page shows a possible duplicate as soon as one exists (for example after a rescan).
- After a capture the card is shown being read: a scan line sweeps it, then each detail it found lights up in
  its field colour with a label (Name, Title, Company, Phone, Email...). Skipped when the phone asks for less motion.

### Fixed
- Scanner no longer loops between "Move closer" and "Card cut off": a card spanning half the view width is close
  enough. Auto-capture tolerates normal hand shake and a flickery frame, and glare or poor light only delays the shot
  (about 1.5 s) instead of blocking it; such cards are flagged for review.

## [0.2.0] - 2026-10-20

### Added
- **Card scanner** (Scan card button, drawer → Scan cards): live card outline, one hint at a time ("Move closer",
  "Hold steady", "Glare, tilt the card", "More light"), automatic capture when the card is clear and steady, manual
  shutter, torch and tap-to-focus.
- Cards are straightened (perspective corrected) to at least 1400 px, read on the phone, and the new-contact form is
  filled in from the card; fields the reader was unsure of are marked amber.
- Back side: add the back of a card after the front; its details fill gaps the front left.
- Several cards at once: photograph a pile on a table, or pick several photos; each card is listed to review and save.
- Pick card photos from the gallery; works without a camera.
- Adjust corners by hand (with a magnifier) when the edges aren't found.
- Dark cards get a second, contrast-boosted reading pass.
- **QR codes on cards** are read too: a contact QR (vCard or MECARD) fills the form and wins over the printed text;
  where the two disagree the field is marked amber. A web-link QR shows its real domain, warns about link shorteners,
  look-alike characters and non-https links, and only opens when you tap it.
- **Review scan** screen: the card with a tappable box on every line of text; tap one and choose which field it
  belongs to, or draw a box with "Read a region" to read just that part. "Save and review next" moves straight on.
- **Review queue** (drawer → Review queue): every scanned card is stored the moment it's read and waits here until
  you check it, with counts for cards saved automatically today, cards to look at, and cards still being read.
  Swipe a card away to remove it (with undo).
- **Batch** scan mode: keep shooting cards one after another while they're read in the background; clear cards go
  straight to Contacts (Settings → "Save clear cards automatically", on by default), the rest wait in the queue.
  **Pile** mode reads several cards in one photo.
- Cards left unread when the app was closed mid-scan are picked up and read the next time it opens.
- **Updates from inside the app**: Settings → Updates → Check for updates shows what's new and installs the latest
  GitHub release over the current one (your contacts are kept). Optional check at startup, off by default; it's the
  only time CardKeep goes online and it sends nothing about you.
- The contact page shows the card (front and back) and opens it full screen to zoom.
- Card photos are stored privately in the app with location and camera data removed; a capture is saved before
  processing so nothing is lost if the app is closed mid-scan.

### Fixed
- Emails that the text reader split with a space ("name@company. com") are joined back up.
- Two phone numbers on one line ("M … O …") each keep their own Mobile/Office label.
- Field confidence now follows the design (on-device reading, parser rule and cross-checks weighted together), so
  clearly printed cards are no longer sent for review unnecessarily.

## [0.1.1] - 2026-10-19

### Added
- Themes in Settings → Appearance: **Light**, **Medium** (grey) and **Dark** (black), all with CardKeep
  orange accents and orange primary controls; the original Navy and brass look stays as a fourth option. Switching is
  instant and remembered.
- **Match phone** theme (the new default): Light when the phone is in light mode, Dark in dark mode, switching live
  when the phone does.

## [0.1.0] - 2026-10-19

First build for phone testing (milestone M1, "Contacts core").

### Added
- Contacts list with search (names, companies, titles, emails, phone digits, notes), sort by name, company or
  recently added, an A–Z index, filters for Hot/Warm/Cold, follow-up due, moved and retired, and multi-select to
  rate, share as vCard or delete.
- Contact detail: call, email, text and share; tap any phone, email, website or address to open it in your
  default app; long-press to copy; lead rating; follow-up date with Done; dated notes; career summary and
  "Check on web" in your default browser.
- Add and edit contacts by hand: several phones (with a live check that the number is valid) and emails, website,
  address, company and title suggestions from existing contacts, lead rating, follow-up, notes and career tracking.
- Delete with Undo.
- Side drawer with every planned area; areas arriving in later versions say which version.
- Settings: phone region and search engine for web checks; version, privacy note and open-source licences.
- CardKeep name, launcher icons (adaptive and themed on Android), and brand mark.
- Debug builds only: OCR capture tool for building the card test set.
- Data layer: full database schema for later versions, card parser groundwork, vCard and CSV writers.
