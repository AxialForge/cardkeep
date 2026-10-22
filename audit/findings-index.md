# Findings index

| ID | Sev | Domain | Status | Blockers | Basis | Confidence | Title |
|---|---|---|---|---|---|---|---|
| MOB-REL-0001 | S4 | 11 | fixed-verified [static] | [data-loss] | runtime | high | Restore swap is not crash-safe; a re-run after a partial swap deletes the user's pre-restore data and opens an empty database |
| MOB-PRV-0001 | S3 | 18 | fixed-verified [artifact] | [privacy, store] | artifact | medium | ML Kit ships Google's datatransport telemetry stack, contradicting the 'only goes online for updates / no analytics' claims |
| MOB-PRV-0002 | S3 | 16 | fixed-verified [static] | [privacy] | static | high | Deleting a contact never removes its data: tombstone only, card photos, logos and contact details kept forever and copied into every backup |
| MOB-REL-0002 | S3 | 11 | fixed-verified [static] | [data-loss] | static | high | Queued scan captures exist only in memory; killing the app during batch scanning loses them |
| MOB-STORE-0001 | S3 | 23 | open | [store] | artifact | high | In-app APK self-updater and REQUEST_INSTALL_PACKAGES are not allowed in a Play build |
| MOB-STORE-0002 | S3 | 23 | fixed-verified [artifact] | [store] | artifact | medium | Plugin-merged READ_MEDIA_IMAGES/VIDEO/AUDIO and RECORD_AUDIO are declared but no feature needs them |
| MOB-REL-0003 | S2 | 11 | fixed-verified [static] | [] | static | high | A failed or bad restore is silent, and the before_restore safety copy cannot be reached from the app |
| MOB-REL-0004 | S2 | 20 | fixed-verified [static] | [] | static | high | An offline or interrupted update download throws an uncaught error and leaves the sheet on its progress bar |
| MOB-SEC-0001 | S2 | 12 | fixed-verified [artifact] | [] | artifact | high | Backup scope is undeclared: allowBackup defaults to true with no dataExtractionRules, so the contacts DB, card photos and weekly backup zips go to Google cloud backup and device transfer |
| MOB-SEC-0100 | S2 | 13 | fixed-verified [static] | [quality] | static | high | CSV import is quadratic: the separator is re-detected by splitting the whole file at every comma, so a few-thousand-row CSV freezes the app |
| MOB-STORE-0003 | S2 | 23 | open | [store] | static | high | CI builds split APKs only; no AAB and no Play App Signing setup |
| MOB-STORE-0004 | S2 | 23 | open | [store] | static | high | No privacy policy URL and no in-app privacy policy link |
| MOB-UX-0001 | S2 | 07 | fixed-verified [static] | [] | runtime | high | Drawer destinations pile up on the back stack; Back walks through every section visited before leaving the app |
| MOB-A11Y-0001 | S1 | 07 | fixed-verified [static] | [] | runtime | high | Round header buttons (DiscButton) are 46x46 dp, below the 48 dp touch-target minimum |
| MOB-A11Y-0002 | S1 | 07 | fixed-verified [static] | [] | runtime | high | Scan mode selector (One card / Batch / Pile) has 34 dp tall touch targets |
| MOB-API-0001 | S1 | 14 | fixed-verified [static] | [] | static | high | Update download falls back to a size-only check when GitHub lists no SHA-256 digest, and has no maximum size |
| MOB-BLD-0002 | S1 | 2 | fixed-verified [static] | [] | static | high | Release build silently falls back to the debug signing key when key.properties is missing |
| MOB-BLD-0003 | S0 | 18 | open (partial: no SBOM/provenance) | [] | static | high | CI actions are pinned to moving major tags, and releases carry no provenance, checksums file or SBOM |
| MOB-BLD-0004 | S1 | 2 | fixed-verified [static] | [] | static | high | R8 mapping and Dart symbol files are not archived, so release crashes cannot be symbolicated |
| MOB-PRV-0003 | S1 | 16 | fixed-verified [static] | [] | static | high | before_restore/ fallback copy of the whole library is kept indefinitely with no way to discard it |
| MOB-PRV-0004 | S1 | 17 | fixed-verified [artifact] | [] | artifact | high | open_filex and camera_android_camerax also merge legacy READ/WRITE_EXTERNAL_STORAGE that the app never uses |
| MOB-REL-0005 | S1 | 11 | fixed-verified [static] | [] | static | medium | A capture that always fails to process is retried on every launch, with a recurring "Reading 1 card left from last time |
| MOB-REL-0006 | S1 | 11 | fixed-verified [static] | [] | static | high | Several multi-step writes are not in a transaction (job change, import, event delete, card link) |
| MOB-REL-0007 | S1 | 11 | fixed-verified [static] | [] | static | medium | Reminder sync calls cancelAll, which also clears today's reminder already shown; ids come from String.hashCode |
| MOB-REL-0008 | S1 | 11 | fixed-verified [static] | [] | static | medium | Card images are content-addressed, but discarding a card deletes them without checking whether another card uses the same hash |
| MOB-REL-0009 | S1 | 11 | fixed-verified [static] | [] | static | high | No test runs the v1 to v2 to v3 schema upgrade, which every restore of an older backup depends on |
| MOB-SEC-0002 | S1 | 12 | fixed-verified [static] | [] | static | high | Follow-up reminders show the contact's name, company and event on the lock screen (no visibility or publicVersion set) |
| MOB-SEC-0003 | S1 | 12 | fixed-verified [static] | [] | static | medium | Camera captures (takePicture files in the cache dir) are read into memory and never deleted |
| MOB-SEC-0006 | S1 | 12 | fixed-verified [static] | [] | static | medium | Incoming vCard intent reads any URI without checking scheme or authority (confused-deputy read of CardKeep's own private files) |
| MOB-SEC-0101 | S1 | 13 | fixed-verified [static] | [] | static | medium | OCR text parser regexes are super-linear on long lines (20k digits 13 s, 50k chars 84 s) |
| MOB-SEC-0102 | S1 | 13 | fixed-verified [static] | [] | static | high | Backup restore trusts the zip's own manifest: unlisted files are staged unverified, the database is not integrity-checked, and there is no size limit |
| MOB-SEC-0103 | S1 | 13 | fixed-verified [static] | [] | static | high | Opening a malformed website value (e.g. 'javascript:alert(1)' from a vCard or QR) throws an uncaught FormatException |
| MOB-STORE-0005 | S1 | 23 | open | [store] | static | high | Data safety answers not prepared; they depend on the Play build contents |
| MOB-STORE-0006 | S1 | 21 | fixed-verified [static] | [quality] | static | high | README is stale: 'What it does (0.2.0)', shipped features listed under 'What's next', removed Medium theme named |
| MOB-STORE-0007 | S1 | 23 | fixed-verified [static] | [] | static | high | Roadmap still names app id com.axialforge.card_organizer; shipped id com.axialforge.cardkeep becomes permanent at first Play upload |
| MOB-UX-0002 | S1 | 06 | fixed-verified [static] | [] | runtime | high | Sync to desktop" is a live drawer entry that opens a "coming in 0.8" placeholder |
| MOB-BLD-0005 | S0 | 2 | fixed-verified [artifact] | [] | artifact | high | APK is signed with scheme v2 only; v3 (key rotation) is not enabled and there is no recorded key backup |
| MOB-PERF-0001 | S0 | 09 | open | [] | runtime | medium | About 80 MB of memory stays allocated after leaving the Scan screen |
| MOB-SEC-0004 | S0 | 12 | fixed-verified [static] | [] | static | high | No FLAG_SECURE or recents protection: contact screens appear in the recents thumbnail and in screenshots |
| MOB-SEC-0005 | S0 | 12 | open | [] | static | high | Contacts database, card images and backup zips are stored unencrypted (roadmap decision D3 still open) |
| MOB-SEC-0007 | S0 | 12 | fixed-verified [static] | [] | static | medium | debugPrint error logging runs in release, and clipboard copies of contact details are not flagged sensitive |
| MOB-AND-0001 | S2 | 3 | duplicate (tracked as MOB-SEC-0001) | [privacy] | artifact | high | Android auto-backup is on by default, so the contacts database and card photos go to Google cloud and device-transfer backups |
| MOB-BLD-0001 | S2 | 2 | duplicate (tracked as MOB-STORE-0002) | [store] | artifact | medium | Shipped APK declares RECORD_AUDIO, READ_MEDIA_VIDEO and READ_MEDIA_AUDIO that the app never uses |
