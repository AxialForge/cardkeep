---
finding_id: MOB-SEC-0102
audit_domain: 13
platform: android
severity: S1
blockers: []
title: "Backup restore trusts the zip's own manifest: unlisted files are staged unverified, the database is not integrity-checked, and there is no size limit"
status: open
confidence: high
evidence_basis: static
affected_component: "lib/core/transfer/backup.dart:78-113 check(), :117-129 stage(); lib/features/transfer/transfer_screens.dart:286-311"
affected_screen: "Settings > Backup > Restore"
affected_version: "0.6.0 (versionCode 2010) cdcf49d"
description: "check() verifies only the hashes the manifest itself lists, so the hashes detect corruption but give no authenticity (expected for an unsigned, user-chosen file). stage() then writes every zip entry except manifest.json into restore_pending/, including entries absent from the manifest, and applyPendingRestore moves restore_pending/cards wholesale, so unlisted card files are restored unverified. The staged SQLite is not checked (PRAGMA quick_check, expected tables) before it replaces the live DB. The whole zip is read into memory and decoded twice (check and stage) with no cap on zip size or uncompressed entry size (zip bomb leads to OOM). Path traversal is correctly blocked (p.isWithin at :124). Impact is limited: the user picks the file and confirms, and the previous data is kept in before_restore/."
expected_behavior: "Stage only manifest-listed files; reject zips above a size cap and entries with excessive uncompressed size; integrity-check the DB before swapping."
observed_behavior: "As described in the cited lines."
evidence:
  - "backup.dart:100-105 verification loops over manifest entries only"
  - "backup.dart:121-127 stages all zip files"
  - "backup.dart:124 isWithin guard present (traversal OK)"
  - "transfer_screens.dart:289 readAsBytes with no size check"
impact:
  security: "A crafted backup can plant extra files under cards/ or a malformed DB; OOM via zip bomb."
  user: "A damaged or hostile backup can be restored and only fail at the next launch (see MOB-REL-0003)."
recommended_remediation: "In stage(), skip names not in the verified manifest; cap zip size and per-entry size; open the staged DB and run PRAGMA quick_check plus a schema sanity check before writing .ready."
verification_procedure: "Unit tests: unlisted entry not staged; an entry expanding to 1 GB refused; corrupt DB refused before .ready."
references:
  owasp_masvs: [MASVS-CODE-4]
  other: [CWE-409, CWE-345]
---
