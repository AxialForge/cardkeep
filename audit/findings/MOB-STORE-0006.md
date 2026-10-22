---
finding_id: MOB-STORE-0006
audit_domain: 21
platform: android
severity: S1
blockers: [quality]
title: "README is stale: 'What it does (0.2.0)', shipped features listed under 'What's next', removed Medium theme named"
status: fixed-verified
confidence: high
evidence_basis: static
affected_component: "README.md sections 'What it does (0.2.0)', 'Themes' bullet, 'What's next'"
affected_version: "0.6.0 (versionCode 2010), commit cdcf49d"
description: "README describes 0.2.0. 'What's next' lists duplicates, tags, events, career tracking, import/export (vCard, CSV, HubSpot) and tap cards (NFC), which CHANGELOG 0.3.0-0.6.0 records as shipped. The Themes bullet says 'Light, Medium and Dark' but 0.6.0 removed Medium and added Navy and brass dark. The GitHub repo description and topics are accurate. When a Play listing is written from this text, the Play Metadata policy requires it to be accurate."
recommended_remediation: "Update README to 0.6.0 features (NFC, import/export, backup/restore, My card, career moves, follow-ups and reminders), fix the themes line, keep only unbuilt items (app lock, PC sync) under 'What's next', refresh screenshots."
verification_procedure: "Every README feature maps to a CHANGELOG entry; no shipped feature appears under 'What's next'."
references:
  google_requirement: "Google Play Metadata policy (applies once a listing exists), checked 2026-10-21: https://support.google.com/googleplay/android-developer/answer/9898842"
---

**Fix (batch C, 2026-10-22).** README rewritten for 0.6 features, themes corrected, What's next updated.

**Verification pass 2026-10-22 (Phase 22): fixed-verified [static].** README 'What it does (0.6)' lists the shipped features; themes line fixed; 'What's next' has only app lock, PC sync and a Play release.
