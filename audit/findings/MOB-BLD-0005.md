---
finding_id: MOB-BLD-0005
audit_domain: 2
platform: android
severity: S0
blockers: []
title: "APK is signed with scheme v2 only; v3 (key rotation) is not enabled and there is no recorded key backup"
status: fixed-verified
confidence: high
evidence_basis: artifact
affected_component: "android/app/build.gradle.kts signingConfigs; keys/ (git-ignored)"
affected_version: "0.6.0 (versionCode 2010 arm64), commit cdcf49d"
evidence:
  - "apksigner verify -v CardKeep-0.6.0-arm64-v8a.apk: v1 false, v2 true, v3 false, v3.1 false, v4 false; 1 signer"
recommended_remediation: "Set enableV3Signing = true in the release signing config; record the keystore backup location in CLAUDE.md."
verification_procedure: "apksigner verify reports v3 true."
references:
  owasp_masvs: [MASVS-CODE-1]
  owasp_mastg: [MASTG-TEST-0038]
  other: []
---

# APK is signed with scheme v2 only; v3 (key rotation) is not enabled and there is no recorded key backup

## Description
apksigner shows v2 only. v2 is sufficient for minSdk 24, but without v3 the key can never be rotated in place for sideloaded users, so loss or compromise of the single key ends the update chain. Where the offline backup of keys/ lives is not recorded in the repo docs.

## Expected behaviour
v2+v3 signatures and a documented key backup.

## Observed behaviour
v2 only.

## Recommended remediation
Set enableV3Signing = true in the release signing config; record the keystore backup location in CLAUDE.md.

## Verification procedure
apksigner verify reports v3 true.

## Fix

enableV3Signing (and v2) in the release signing config; docs/RELEASE-SIGNING.md records the key-backup rule.

**Verification pass 2026-10-22 (Phase 22): fixed-verified [artifact].** apksigner verify app-x86_64-release.apk (HEAD 495b258, 0.6.1 versionCode 4011, sha256 9ff12000...295b676d): v2 true, v3 true; signer SHA-256 4ffa7fe0...3a2820 (unchanged). docs/RELEASE-SIGNING.md records the key-backup rule (the off-PC copy is still a manual check).
