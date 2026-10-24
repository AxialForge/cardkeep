# Changelog

All notable changes to CardKeep. Format: [Keep a Changelog](https://keepachangelog.com/), versions: [SemVer](https://semver.org/).

## [0.7.2] - 2026-10-23

### Added

- **Sweep scan** (S14c): lay the cards out and move the phone slowly over them. Each card is outlined in the accent colour
  when found, captured by itself once it is steady, shown with an accent wipe while it is read, then turns green with
  "Done" (amber "Hover again" when it could not be read). A counter shows "7 of 9 done"; Finish opens the review queue.
  Each card is read once; a card already captured shows "Already in queue". New **Sweep** mode on the scanner and
  **Sweep across cards** in the **+** menu.
- **Your own place categories** (S14b.6): Settings > Place categories adds, renames, reorders and deletes them (Other
  stays); a **+ New** chip on a place's form adds one on the spot. A rename shows everywhere; deleting one moves its
  places to Other. Exports carry the category name (vCard X-CARDKEEP-CATEGORY, CSV Category column) and imports add it.
  Database schema v5.
- **Remove all** in the Review queue (⋮ menu) with one Undo that stays on screen until used.

### Changed

- Sweep reads every card from a full-resolution photo taken while you hold steady, cut flat along the card with its neighbours blanked out, and tries all four turns so cards come out upright. Clear cards go straight to Contacts; the rest wait in the queue.
- Long-press the Sweep counter to show the speed and why a card is still waiting.

### Fixed

- Phone numbers followed by a label ("216.432.5822 office / cell / fax") get the right type.
- The same card shot twice is spotted even when the reading differs a little; a shared main office number no longer marks a different person as a repeat.

## [0.7.1] - 2026-10-23

### Added

- **Merge all obvious duplicates** on the Duplicates screen (S14d.1): copies with the same name and the same email or
  phone at the same company are grouped, previewed, merged into the copy with the newest card in one go, and undone with
  one Undo. Places are never merged with people.
- **Company pages** (S14d.2, S14d.3): tap a company on a contact page, a company header in the Company view, or a company
  in search results. It shows everyone there now and before, its places, the events where you met them, shared phones and
  website, and the last card date; add a person at the company or share everyone as one vCard file.

### Fixed

- A bulk merge keeps the company most copies agree on (preferring LLC/Inc or the email's domain, never a slogan) and shows it in the preview.
- Undo for a bulk merge stays at the top of Duplicates until used, instead of disappearing with the message.

## [0.7.0] - 2026-10-23

### Added

- **Places** (S14b): cards that belong to a business, not a person (store, restaurant, vendor, service). A place keeps
  its business name, category, opening hours, phones, website, address, notes, tags and card photos.
- Scanning recognises place cards (opening hours, shop slogans, store/restaurant/vendor/service words, an address) and
  fills the business name, category and hours; a Person/Place switch on the form changes it.
- Contacts: a building icon for places without a logo, a **Places** filter, and places sort by business name. A place's
  page shows its hours and category and leaves out career tracking.
- vCard import and export mark places as organisations (KIND:org in 4.0, X-ABShowAs:COMPANY in 3.0) with their hours;
  CardKeep's own CSV gains Type and Hours columns. Two places with the same name and phone or address are suggested as
  duplicates; a place never matches a person.
- Database schema v4 (kind, place category, hours); existing contacts upgrade as people.

### Changed

- Settings: theme pills with a light and a dark version of each look; Match phone is now a switch.
- One card scanning always goes through, even for a card scanned a moment ago; Batch and Pile still skip repeats.

### Fixed

- Names with a title or credential ("Dr. Philip J Znidarsic DDS") read correctly; the credential is kept in Notes.
- A company printed over two lines ("BRIGHTWATER" / "Family Dental") is joined, and the second line is never taken as a name.
- "NAME, TITLE" on one line is split; .games and other newer web endings are read whole; "www." never becomes a company.
- Phone labels like Sales, Main and Support no longer become a title; "Visit us:" is dropped from addresses.
- Opening hours keep their spacing, and all-caps taglines are kept.
- Gallery photos of busy cards come out upright more often.

## [0.6.3] - 2026-10-23

Fixes from the 0.6.2 phone test on a Galaxy S25 Ultra.

### Added

- **Add the back side** on every card in the review queue, so backs can be added after Batch or Pile.
- A purple **QR** box marks a QR code found on a card; a QR link fills Website.
- Pile and Batch give feedback at each capture (flash, buzz, "3 cards found") and skip a card already captured.

### Changed

- Phone numbers get their own full-width line in the edit and review forms.
- The drawer scrolls as one list with a hint, so every entry is reachable at any font size.
- **+** menu: "Scan many cards" (Batch) and "Scan a pile" (several cards in one photo).
- Card photos are stored at most 2000 px, so a contact takes well under 1 MB.
- All-caps company names are written normally ("Northwind Forging Inc."), keeping LLC, USA and similar.

### Fixed

- Card reading: printed company names win over logo words and email guesses; M/T/C/D phone labels; country joins the address; middle initials; all-caps titles; long web endings (.example, .company); taglines no longer taken as names; unsure emails kept and flagged; no stray letters in Notes; a logo letter glued to the company is dropped.
- Pile no longer adds each card twice, and cut-outs and adjusted cards come out upright.
- **Save clear cards automatically** now saves clear cards.
- Adjust corners: the handle sits off the corner with a magnifier, so you can see what you are aligning.
- Field tags no longer cover other text on the card image.
- Logos: no blank patches or QR codes as a contact's logo.
- Small cards and cards on white paper are cut out more often.
- The torch stays on after Retake.
- "1 person across 1 company" and other singular counts.
- The Scan card button hides while typing; the A-Z index sits below the filters and a tap on a letter jumps there.
- Calls, email and maps open in their own app, so Back from CardKeep goes home.
- The duplicate card's buttons fit on narrow screens; the tag colour shows as selected.
- Hide in recent apps clears the older switcher snapshot.
- A follow-up due today gets a reminder, and notification permission is asked for any follow-up.
- Tap cards notices NFC being turned off or on.
- Importing a contact you have now adds their new notes and title.
- Undo messages close after a few seconds instead of staying on screen.
## [0.6.2] - 2026-10-22
### Added
- **Hide in recent apps** (Settings > Privacy, off by default): blanks CardKeep in the app switcher and blocks screenshots.
- **Data from before the last restore** (Export and backup): go back to it or discard it; it is removed after 30 days.

### Changed
- Contacts are no longer included in Google cloud backup or device transfer.
- Unused permissions (microphone, media, storage) removed.
- Reminders no longer show the contact on the lock screen.
- "Sync to desktop" is hidden until it exists; Back from any section returns to Contacts.
- Larger touch targets on the round header buttons and the scan mode selector.

### Fixed
- Restoring checks the backup more strictly (unlisted files, database integrity, size limits).
- An update download that fails or is cut off says so instead of hanging; updates must match GitHub's checksum.
- A capture that cannot be read after 3 tries is set aside instead of retried on every start.
- Large CSV imports and very long text on a card no longer freeze the app; a bad web address no longer crashes it.
- Job changes, imports, event deletes and card links are saved all-or-nothing.
- Discarding a card no longer deletes an image another card still uses.

## [0.6.1] - 2026-10-22
### Fixed
- A restore interrupted at any point (phone off, app killed) now finishes on the next start; nothing is lost, and you are told whether it worked.
- Cards captured but not yet read are kept on disk until they are in the review queue, so closing the app mid-scan no longer loses them.
- Deleted contacts are wiped for good after 7 days, with their card photos and logos, and are never included in backups.
- ML Kit's usage logging to Google is switched off: text recognition stays fully on the phone.
## [0.6.0] - 2026-10-21
### Added
- **Tap cards (NFC)** (drawer, or + → Tap an NFC card): hold a tap card to the back of the phone, then the next one;
  each gives a buzz and a row. A contact card opens the review form to save (with the open event and the duplicate
  and job-change checks); a link card can be opened in your browser or saved as a link only (tagged "NFC link"); text
  can be copied. The same card tapped again within 3 seconds is ignored, including cards whose link changes on every
  tap. Payment cards and door badges are not read. With NFC off there's a button to its settings.

## [0.5.0] - 2026-10-21
### Added
- **Export** (drawer → Export and backup): everyone, a tag or an event, as vCard 3.0/4.0, CSV, HubSpot CSV or
  Salesforce CSV; with or without notes; optionally zipped with the card photos. **Share**, or **Save to…** any
  folder. Phone extensions and fax numbers are included.
- **Import** (drawer): vCard files (also by opening or sharing a .vcf from another app) and spreadsheets (.csv) with
  a column-matching screen and preview; the matching is remembered. Imported people get the **Imported** tag;
  someone you already have is updated instead of added twice, and someone at a new company shows up in Career moves.
- **Backup and restore**: one zip with contacts, card photos, tags, events and settings, checked before restoring
  (refuses damaged files and backups from a newer CardKeep). Your current data is kept as a fallback copy.
  Optional **weekly backup** on the phone (last 4 kept).
- **My card**: your own details as a QR code (tap for full screen at full brightness) and as a contact file to share.

## [0.4.0] - 2026-10-21
### Added
- **Career moves** (drawer): when a new card shows someone you have at another company, or you mark an email as
  bounced (long-press it), they're listed to confirm. **Add as new role, keep history** (the old job and work email
  stay as history), **Replace old details**, or **Different person**.
- **Changed jobs…** and **Mark retired…** in a contact's ⋯ menu, with an optional replacement: their page shows
  **Replaced by** (with call and email), the replacement's shows **Replaces**, and an open follow-up can move to
  the replacement. **Not retired** undoes it.
- Settings: **Career tracking** on or off for everyone (each contact can still opt out on their edit page).

## [0.3.1] - 2026-10-21
### Added
- **Follow-ups** (drawer, or the "due this week" banner): Overdue, This week and Later. Mark one done, push it to
  tomorrow, 3 days or next week, or **draft the follow-up email** in your mail app (marked done only when you say
  it was sent).
- **Reminders**: a notification on the follow-up day (around 8:00); tapping it opens the contact. Android asks once
  for permission. Reminders survive a restart of the phone.
- Event page: **Follow up with everyone** sets a follow-up for everyone met there, on the end date plus the event's
  reminder days.

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
