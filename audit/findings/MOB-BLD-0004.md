---
finding_id: MOB-BLD-0004
audit_domain: 2
platform: android
severity: S1
blockers: []
title: "R8 mapping and Dart symbol files are not archived, so release crashes cannot be symbolicated"
status: fixed (unverified)
confidence: high
evidence_basis: static
affected_component: ".github/workflows/release.yml (flutter build apk --release --split-per-abi)"
affected_version: "0.6.0 (versionCode 2010 arm64), commit cdcf49d"
evidence:
  - "release.yml: only build/app/outputs/flutter-apk/CardKeep-*.apk are uploaded"
  - "unzip -l arm64 APK: no mapping.txt or symbol files in the package (correct)"
recommended_remediation: "Upload build/app/outputs/mapping/release/mapping.txt with actions/upload-artifact (long retention) or as a release asset."
verification_procedure: "Next tag's workflow run lists a mapping artifact."
references:
  owasp_masvs: []
  owasp_mastg: []
  other: []
---

# R8 mapping and Dart symbol files are not archived, so release crashes cannot be symbolicated

## Description
R8 runs on release (proguard-rules.pro is applied, and CLAUDE.md records a 0.2.x R8 stripping bug found only in release), but mapping.txt is discarded with the runner and Dart code is not built with --split-debug-info, so no symbol files exist for the shipped binaries. No user risk; it limits diagnosing field crashes.

## Expected behaviour
mapping.txt (and symbols if adopted) retained per release.

## Observed behaviour
Not retained.

## Recommended remediation
Upload build/app/outputs/mapping/release/mapping.txt with actions/upload-artifact (long retention) or as a release asset.

## Verification procedure
Next tag's workflow run lists a mapping artifact.

## Fix

Release CI builds with --split-debug-info and publishes CardKeep-<v>-symbols.zip and CardKeep-<v>-mapping.txt as release assets and a workflow artifact.
