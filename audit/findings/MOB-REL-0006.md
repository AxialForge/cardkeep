---
finding_id: MOB-REL-0006
audit_domain: 11
platform: android
severity: S1
blockers: []
title: Several multi-step writes are not in a transaction (job change, import, event delete, card link)
status: fixed-verified
confidence: high
evidence_basis: static
affected_component: lib/core/career/career_repository.dart:266-330, lib/core/transfer/transfer_repository.dart:157-196, lib/core/events/events_repository.dart:116-122, lib/core/cards/card_queue_repository.dart:83-117
affected_screen: Contact > Mark as moved; Import; Events > Delete; Review queue > Save
affected_version: 0.6.0 (2010) cdcf49d
---

**Description.** Merge, undo, retire, moveFollowup, contact save/delete/restore and the tag operations all use `db.transaction` (12 call sites). The methods below do not:

- **`changeJob`** marks the old role *former* (`:281`), inserts the new role, and then updates emails and roles. An error after the first write leaves the person with no current role.
- **`importContacts`** saves each contact, then merges or tombstones it in separate steps. A kill partway through leaves the file half imported, and "skipped" duplicates leave tombstoned rows behind.
- **`EventsRepository.delete`** ends the event's sessions and tombstones the event in two separate statements.
- **`CardQueueRepository.link`** runs up to three updates: the logo, the met-at event, and the card status. If it fails after the person is updated, the card stays in the queue, and a retried `autoSave` creates a duplicate contact.

These statements are quick, so being killed between them is unlikely. Errors are the more realistic trigger.

**Remediation.** Wrap each of these method bodies in `db.transaction`. For import, use one transaction per contact.

**Verification.** Fault-injection tests that make a later step throw, then assert that no partial rows remain.

**Fix (batch C, 2026-10-22).** changeJob, event delete, card link and each imported contact now run in a db.transaction.

**Verification pass 2026-10-22 (Phase 22): fixed-verified [static].** db.transaction around the CareerRepository job change, TransferRepository per-contact import, EventsRepository.delete and CardQueueRepository.link (495b258).
