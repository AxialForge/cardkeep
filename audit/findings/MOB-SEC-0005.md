---
finding_id: MOB-SEC-0005
audit_domain: 12
platform: android
severity: S0
blockers: []
title: "Contacts database, card images and backup zips are stored unencrypted (roadmap decision D3 still open)"
status: open
confidence: high
evidence_basis: static
affected_component: "app_flutter/card_organizer.sqlite, app_flutter/cards/**, app_flutter/backups/*.zip; lib/core/transfer/backup.dart:38-50"
affected_version: "0.6.0 (2010) cdcf49d"
description: "Data is protected only by the Android sandbox and file-based encryption. For this threat model (unlocked phone out of scope, no credentials or secrets stored) that meets MASVS L1; this is recorded so that D3 is decided explicitly. Two parts leave the sandbox in plaintext: the database also goes to cloud backup (MOB-SEC-0001), and exported backup zips hold the raw SQLite file and images, readable by anyone who gets the file from Drive, email or a USB stick."
evidence:
  - "lib/core/transfer/backup.dart:40-50 backup zip contains the raw sqlite copy and every card image, with no encryption"
  - "audit/A-scope-method-evidence.md stack: drift (SQLite + FTS5), no SQLCipher"
recommended_remediation: "Decide D3. At minimum, consider an optional passphrase on exported backup zips, since they are the copy that leaves the device."
references:
  owasp_masvs: [MASVS-STORAGE-1]
  owasp_maswe: [MASWE-0006]
  owasp_mastg: [MASTG-TEST-0001]
  other: [CWE-311]
---
