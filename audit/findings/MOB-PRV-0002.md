---
finding_id: MOB-PRV-0002
audit_domain: 16
platform: android
severity: S3
blockers: [privacy]
title: "Deleting a contact never removes its data: tombstone only, card photos, logos and contact details kept forever and copied into every backup"
status: open
confidence: high
evidence_basis: static
affected_component: "lib/core/contacts/contacts_repository.dart:343-346; lib/core/db/database.dart:61-67; lib/core/transfer/backup.dart:42; lib/core/images/image_store.dart:66-70"
affected_screen: "Contact detail > Delete"
affected_version: "0.6.0 (2010) cdcf49d"
description: "ContactsRepository.delete() only sets people.deleted_at and removes the FTS row. The person's roles, contact_points (phones, emails, addresses), notes, person_tags, cards rows, and the card image files (original/rectified/thumb) and logo stay on disk indefinitely; nothing in lib/ ever purges tombstoned rows. Backups use VACUUM INTO, so deleted contacts travel in every manual and weekly automatic backup and come back on restore (still tombstoned). ImageStore.delete() also never removes logo/ files, so even a queue-card delete leaves the logo. The user is shown the contact as deleted. Tombstones exist for future sync (not built). S3: personal data of third parties the user chose to delete is retained without limit and exported off-device in backups."
preconditions: "A saved contact with a card photo."
steps_to_reproduce:
  - "Save a contact from a scanned card, then delete it and let the undo snackbar expire"
  - "adb shell run-as com.axialforge.cardkeep: copy app_flutter/card_organizer.sqlite out and query people, contact_points, cards for that uuid"
  - "ls app_flutter/cards/original rectified thumb logo"
  - "Make a backup and list the zip"
expected_behavior: "After the undo window (or a stated retention such as 30 days) the person, child rows, card images and logo are purged; later backups do not contain them."
observed_behavior: "Row tombstoned; all child rows and files remain; included in backups."
evidence:
  - "lib/core/db/database.dart:61 '/// Tombstone, never hard-delete, so sync can propagate it (spec §10).'"
  - "lib/core/contacts/contacts_repository.dart:343-346: delete() = tombstonePerson(id) + DELETE FROM person_search"
  - "lib/core/transfer/backup.dart:42: VACUUM INTO copies every row including tombstones; :46-52 copies every file under cards/"
  - "lib/core/images/image_store.dart:66-70: delete() covers original, rectified, thumb only (not logo)"
  - "grep for DELETE FROM / purge of deleted_at rows in lib/: only person_search deletes"
impact:
  security: "None direct."
  privacy: "Deletion does not delete; data minimisation and retention failure; deleted data leaves the device in backup zips the user shares."
  user: "Storage grows; a privacy-minded 'delete' is ineffective."
  business: "A Play Data Safety 'data can be deleted' answer would be inaccurate."
root_cause: "Sync-oriented tombstoning adopted before sync exists, with no purge step."
recommended_remediation: "Add a purge (on start or weekly) for tombstoned people older than N days: cascade-delete child rows and delete card and logo files no longer referenced. Exclude tombstoned rows and their images from backups. State retention in the privacy policy. When sync arrives, keep only the id + deleted_at tombstone."
verification_procedure: "Delete a contact, advance the clock past retention, confirm rows and files are gone and a new backup does not contain them."
references:
  owasp_masvs: [MASVS-PRIVACY-2, MASVS-STORAGE-2]
  google_requirement: "Play Data safety - data deletion (checked 2026-10-21)"
---
See front matter.
