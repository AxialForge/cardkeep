# CardKeep

<img src="design/branding/CardKeep-mark-1024.png" width="96" align="right" alt="CardKeep logo">

**A business card organizer that keeps everything on your phone.** Photograph a card and CardKeep straightens it,
reads it, fills in the contact and keeps the card with them. No account, no cloud, no tracking.

<p>
  <img src="docs/screenshots/contacts-light.png" width="200" alt="Contacts list">
  <img src="docs/screenshots/review-scan.png" width="200" alt="Review a scanned card">
  <img src="docs/screenshots/review-queue.png" width="200" alt="Review queue">
  <img src="docs/screenshots/contact-detail.png" width="200" alt="Contact with its card">
</p>

## What it does (0.7)

- **Scan cards with the camera.** It finds the card, waits until it's sharp and steady, and captures by itself.
  Glare, blur, low light and cut-off cards get a hint before the shot and a flag after it.
- **Read on the phone.** The card is straightened and read with on-device text recognition; name, title, company,
  phones, emails, website and address land in the right fields. Anything it isn't sure of is marked for a second look.
- **QR codes too.** A contact QR on the card fills the details exactly. A web-link QR shows the real site, warns about
  link shorteners and look-alike addresses, and only opens when you tap it.
- **Batch and pile.** Shoot a stack of cards one after another, or several on a table in one photo. Clear cards go
  straight to Contacts; the rest wait in a review queue. Nothing is lost if the app closes mid-scan.
- **Sweep scan.** Lay the cards out and move the phone over them: each card is outlined, read on its own and marked
  Done in green as you go.
- **Review fast.** Tap any line of text on the card to put it in a field, or draw a box to read just that part.
- **Your contacts, quickly.** Search by any part of a name, company, email or phone number. Call, text, email, open
  the website or the address in your own apps. Lead ratings, follow-up dates, dated notes and a "check on web" search.
- **Duplicates and merging.** Possible duplicates are found as you add people; merge them side by side, or clean up every
  obvious copy at once (same name plus the same email or phone) with a preview and one Undo.
- **Companies and career moves.** People are grouped by company, and each company has its own page: everyone there now
  and before, its places, the events where you met them, shared phone and website, and the last card date. A new card at another
  company becomes a job change you confirm; retirements and successors are tracked.
- **Tags, events and follow-ups.** Tag anyone, run an event as a scan session so new cards remember where you met, and
  set follow-up dates with reminders on the day.
- **Import, export and backup.** vCard and CSV (Google, Outlook, HubSpot, Salesforce, LinkedIn) in and out, a full
  backup zip you can restore, and an optional weekly automatic backup. Deleted contacts are wiped for good after 7 days.
- **Places.** Store, restaurant, vendor and service cards are kept as places: business name, category, opening
  hours, phone, website and address (opens Maps). Found automatically when scanned, with a Person/Place switch on the
  form and a Places filter in Contacts. vCard export marks them as organisations (KIND:org).
- **My card and tap cards (NFC).** Share your own card as a QR code, and read or write NFC business cards.
- **Themes.** Light, Dark, Navy and brass, Navy and brass dark, or follow the phone's dark mode.
- **Updates from inside the app** (Settings → Updates), only when you ask.

<p>
  <img src="docs/screenshots/scan-camera.png" width="160" alt="Scanner">
  <img src="docs/screenshots/follow-ups.png" width="160" alt="Follow-ups">
  <img src="docs/screenshots/duplicates.png" width="160" alt="Duplicates">
  <img src="docs/screenshots/export-backup.png" width="160" alt="Export and backup">
  <img src="docs/screenshots/settings.png" width="160" alt="Settings">
</p>

## Install (Android)

1. Open the [latest release](../../releases/latest) on your phone and download `CardKeep-<version>-arm64-v8a.apk`
   (most phones from the last several years; use `armeabi-v7a` for older 32-bit phones).
2. Open the file and allow installing from your browser or files app when Android asks.
3. Open **CardKeep**.

**Updating:** Settings → Updates → *Check for updates* downloads and installs the new version over the old one.
Your contacts stay. Installing a newer APK by hand works the same way; there's no need to uninstall.

Each release also lists `SHA256SUMS.txt` to check a download. The full guide (permissions, backups before changing
phones, building from source) is the Install Manual in [docs/manual/install-manual.md](docs/manual/install-manual.md);
how to use every screen is in the [User Manual](docs/manual/user-manual.md).

## Privacy

- Your contacts and card photos stay in CardKeep's private storage on the phone. Photos are saved without location
  or camera data.
- Cards are read on the phone; nothing is uploaded. No account, no analytics, no ads.
- Links, calls, emails and maps open in your own apps.
- The only time CardKeep goes online is when you check for updates (it asks GitHub for the latest release and sends
  nothing about you). Checking at startup is off unless you turn it on. Downloads must match GitHub's checksum.
- CardKeep is left out of Android's cloud backup and device transfer, so make a CardKeep backup before changing
  phones. Google's ML Kit usage logging is switched off.
- Reminders hide the contact on the lock screen; *Hide in recent apps* (Settings) keeps the app out of the app switcher.

## What's next

App lock, sync with a Windows PC, and a Google Play release (0.6.2 passed a release audit for GitHub distribution;
the Play build is next). The full plan is in [docs/ROADMAP.md](docs/ROADMAP.md); what changed in each version is in
[CHANGELOG.md](CHANGELOG.md).

## Building

Flutter 3.47. On Windows, OpenCV builds from source and needs the Android NDK path (see [CLAUDE.md](CLAUDE.md),
Commands and Gotchas).

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter run
```
