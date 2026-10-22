---
finding_id: MOB-PRV-0003
audit_domain: 16
platform: android
severity: S1
blockers: []
title: "before_restore/ fallback copy of the whole library is kept indefinitely with no way to discard it"
status: open
confidence: high
evidence_basis: static
affected_component: "lib/core/transfer/backup.dart:168-186 (applyPendingRestore)"
affected_screen: "Settings > Backup > Restore"
affected_version: "0.6.0 (2010) cdcf49d"
description: "Each restore moves the previous database and all card images into app_flutter/before_restore/ and keeps them until the next restore replaces them. There is no expiry, no UI to remove it and no mention of it, so a full second copy of personal data (including contacts the user deleted) stays on the phone and storage doubles. The safety copy itself is good practice (data-loss protection); only the unlimited retention is the issue. Automatic backups keep the newest 4 weekly zips (backup.dart:136-155), which is bounded but should be stated in the policy."
expected_behavior: "Fallback kept until the user confirms the restore or for a stated period, then deleted."
observed_behavior: "Kept until the next restore, i.e. typically forever."
evidence:
  - "lib/core/transfer/backup.dart:173-178: rename db, -wal, -shm and cards/ into before_restore/"
  - "lib/core/transfer/backup.dart:174: the only deletion of before_restore/ happens at the next restore"
impact:
  privacy: "Retention without a purpose limit."
  user: "Hidden storage use."
recommended_remediation: "After a restore, offer 'Everything looks right - remove the old copy'; auto-delete after e.g. 30 days; mention in the privacy policy."
verification_procedure: "After confirmation or expiry, before_restore/ no longer exists."
references:
  owasp_masvs: [MASVS-PRIVACY-2]
---
See front matter.
