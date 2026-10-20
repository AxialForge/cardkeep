# Changelog

All notable changes to CardKeep. Format: [Keep a Changelog](https://keepachangelog.com/), versions: [SemVer](https://semver.org/).

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
