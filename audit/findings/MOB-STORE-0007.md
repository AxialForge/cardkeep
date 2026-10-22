---
finding_id: MOB-STORE-0007
audit_domain: 23
platform: android
severity: S1
blockers: []
title: "Roadmap still names app id com.axialforge.card_organizer; shipped id com.axialforge.cardkeep becomes permanent at first Play upload"
status: open
confidence: high
evidence_basis: static
affected_component: "docs/ROADMAP.md:96-97 (S0.14, S0.15), :580 (D1)"
affected_version: "0.6.0 (versionCode 2010), commit cdcf49d"
description: "S0.14 and D1 still give the final id as com.axialforge.card_organizer and the name as 'Card Organizer', while the app ships as CardKeep / com.axialforge.cardkeep. A package name cannot change after the first Play upload, so the decision should be closed explicitly before M9. Docs drift only."
recommended_remediation: "Mark S0.14, S0.15 and D1 decided (com.axialforge.cardkeep, CardKeep) and confirm the Play listing name."
verification_procedure: "ROADMAP rows updated."
references:
  google_requirement: "Play Console app creation: package name is permanent, checked 2026-10-21: https://support.google.com/googleplay/android-developer/answer/9859152"
---
