---
finding_id: MOB-REL-0009
audit_domain: 11
platform: android
severity: S1
blockers: []
title: No test runs the v1 to v2 to v3 schema upgrade, which every restore of an older backup depends on
status: open
confidence: high
evidence_basis: static
affected_component: lib/core/db/database.dart:47-55, test/db/schema_test.dart
affected_version: 0.6.0 (2010) cdcf49d
---

**Description.** `onUpgrade` creates `not_duplicates` at v2 and adds 4 columns at v3 (`tables.dart:43-45, 83`). The new columns are nullable or have constant defaults, and the FTS table and indexes are untouched, so static review finds the upgrade correct.

No test, however, opens a v1 or v2 database and upgrades it:
- `grep -rn migrat test` finds nothing;
- `schema_test.dart` only checks a fresh create;
- there are no drift schema dumps.

`backup.dart:168` relies on older backups being "migrated by the normal upgrade", so this untested path runs on every restore of an older backup.

**Remediation.** Add `drift_dev schema dump` snapshots for v1 to v3 and a `SchemaVerifier` migration test, plus a test that restores a v1 backup fixture.

**Verification.** The new tests pass in CI.
