---
finding_id: MOB-STORE-0004
audit_domain: 23
platform: android
severity: S2
blockers: [store]
title: "No privacy policy URL and no in-app privacy policy link"
status: open
confidence: high
evidence_basis: static
affected_component: "lib/features/settings/settings_screen.dart:185 (Privacy tile is a one-line statement, no link); ROADMAP S15.11 and S17.6 open"
affected_screen: "Settings > Privacy"
affected_version: "0.6.0 (versionCode 2010), commit cdcf49d"
description: "Play requires a privacy policy link in Play Console and inside the app for every app, and CardKeep handles personal data (contact details, card photos). No policy is published and the app shows only 'No account, no cloud, no analytics...' without a link. The README Privacy section is accurate but is not a policy. Only matters for Play; for GitHub the README statement is adequate."
recommended_remediation: "Publish a privacy policy on GitHub Pages (S17.6) covering on-device storage, on-device OCR, the camera, notifications, backup/export files, the GitHub update check (absent in the Play build) and any link fetch; link it from Settings (S15.11) and the Play listing."
verification_procedure: "URL resolves publicly; Settings has a tappable privacy policy link; Play Console field filled."
references:
  google_requirement: "Google Play User Data policy (privacy policy), checked 2026-10-21: https://support.google.com/googleplay/android-developer/answer/10144311"
---
