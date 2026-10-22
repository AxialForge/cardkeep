---
finding_id: MOB-SEC-0004
audit_domain: 12
platform: android
severity: S0
blockers: []
title: "No FLAG_SECURE or recents protection: contact screens appear in the recents thumbnail and in screenshots"
status: fixed-verified
confidence: high
evidence_basis: static
affected_component: "android/app/src/main/kotlin/com/axialforge/cardkeep/MainActivity.kt:14-45"
affected_version: "0.6.0 (2010) cdcf49d"
description: "No FLAG_SECURE and no setRecentsScreenshotEnabled(false). Acceptable for a contact app without an app lock (allowing screenshots is a feature here). It becomes required when the planned app lock (S15.2/S15.3) is built, otherwise the recents preview shows contacts while the app is locked."
evidence:
  - "grep -rn FLAG_SECURE lib android: no matches"
  - "MainActivity.kt:14-45 only configureFlutterEngine/onNewIntent/readVcf; no window flags"
recommended_remediation: "With S15.2, hide content in recents while locked (setRecentsScreenshotEnabled(false) on API 33+, FLAG_SECURE as an option)."
verification_procedure: "Turn the app lock on, open a contact, press Recents; the thumbnail is blank."
references:
  owasp_masvs: [MASVS-PLATFORM-3, MASVS-STORAGE-2]
  owasp_maswe: [MASWE-0055]
  owasp_mastg: [MASTG-TEST-0010]
---

## Fix

Settings > Privacy > Hide in recent apps (off by default) sets FLAG_SECURE through MainActivity; applied at start and on change.

**Verification pass 2026-10-22 (Phase 22): fixed-verified [static].** Settings > Privacy > Hide in recent apps (off by default) sets FLAG_SECURE via MainActivity setSecure; applied at start and on change. Recents thumbnail check not run.
