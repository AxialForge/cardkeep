---
finding_id: MOB-BLD-0002
audit_domain: 2
platform: android
severity: S1
blockers: []
title: "Release build silently falls back to the debug signing key when key.properties is missing"
status: fixed-verified
confidence: high
evidence_basis: static
affected_component: "android/app/build.gradle.kts:47"
affected_version: "0.6.0 (versionCode 2010 arm64), commit cdcf49d"
evidence:
  - "android/app/build.gradle.kts:10-14 comment: release builds fall back to the debug key"
  - "android/app/build.gradle.kts:47 signingConfig = signingConfigs.findByName('release') ?: signingConfigs.getByName('debug')"
  - ".github/workflows/release.yml: no apksigner verify step before softprops/action-gh-release@v2"
recommended_remediation: "Fail the build in CI when key.properties is missing (e.g. if System.getenv('CI') != null), and add `apksigner verify --print-certs` compared to the known cert SHA-256 (4ffa7fe0...3a2820) before publishing."
verification_procedure: "Run the release workflow on a throwaway tag with the keystore secret removed: it must fail."
references:
  owasp_masvs: [MASVS-CODE-1]
  owasp_mastg: [MASTG-TEST-0038]
  other: []
---

# Release build silently falls back to the debug signing key when key.properties is missing

## Description
If key.properties is absent (a CI secret unset or renamed), `flutter build apk --release` still succeeds and signs with the debug key, and release.yml would publish it. Installed users could not update to it (signature mismatch fails safe), but a debug-signed public release breaks the update chain. No CI step verifies the signer certificate before upload.

## Expected behaviour
A tag build fails if the release key is unavailable, and CI checks the signer SHA-256 against the known release certificate.

## Observed behaviour
Silent fallback; no certificate check.

## Recommended remediation
Fail the build in CI when key.properties is missing (e.g. if System.getenv('CI') != null), and add `apksigner verify --print-certs` compared to the known cert SHA-256 (4ffa7fe0...3a2820) before publishing.

## Verification procedure
Run the release workflow on a throwaway tag with the keystore secret removed: it must fail.

## Fix

Release signing no longer falls back to the debug key: the build stops without android/key.properties unless CARDKEEP_DEBUG_SIGNING=1. CI writes key.properties, so it is unaffected.

**Verification pass 2026-10-22 (Phase 22): fixed-verified [static].** build.gradle.kts: signingConfig is null without key.properties unless CARDKEEP_DEBUG_SIGNING=1, and taskGraph.whenReady throws GradleException for assembleRelease/bundleRelease. A throwaway-tag CI run without the secret was not performed.
