---
finding_id: MOB-REL-0008
audit_domain: 11
platform: android
severity: S1
blockers: []
title: Card images are content-addressed, but discarding a card deletes them without checking whether another card uses the same hash
status: open
confidence: medium
evidence_basis: static
affected_component: lib/core/images/image_store.dart:44-57 and 66-70, lib/core/cards/card_queue_repository.dart:120-131
affected_screen: Review queue > Discard (and Undo)
affected_version: 0.6.0 (2010) cdcf49d
---

**Description.** `commit` stores image files by sha256 and skips files that already exist ("Idempotent"). Rectification is deterministic, so importing the same gallery photo twice creates two `cards` rows with the same `front_sha256`. `discard(cardId)` calls `store.delete(hash)` without checking whether another live card still references that hash. The other card, which may already be saved to a contact, loses its images.

Undo (`restore`) brings back the card row but not the deleted files.

**Remediation.**
- Delete the files only when no live card references the hash.
- Delay file deletion until the undo window has closed.

**Verification.** Test: create two cards with the same hash, discard one, and assert that the other card's files still exist. Also assert that undo restores the images.
