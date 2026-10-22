---
finding_id: MOB-BLD-0003
audit_domain: 18
platform: android
severity: S0
blockers: []
title: "CI actions are pinned to moving major tags, and releases carry no provenance, checksums file or SBOM"
status: open
confidence: high
evidence_basis: static
affected_component: ".github/workflows/release.yml, .github/workflows/ci.yml"
affected_version: "0.6.0 (versionCode 2010 arm64), commit cdcf49d"
evidence:
  - ".github/workflows/release.yml uses: actions/checkout@v4, actions/setup-java@v4, subosito/flutter-action@v2, softprops/action-gh-release@v2"
  - "release.yml 'Signing key' step decodes secrets.ANDROID_KEYSTORE_B64 in the same job (secret values not inspected; referenced via secrets.* only, nothing hardcoded)"
  - "release.yml: permissions contents: write"
recommended_remediation: "Pin each action to a commit SHA (Dependabot can bump them), add actions/attest-build-provenance and a SHA256SUMS asset, optionally generate a CycloneDX SBOM in CI."
verification_procedure: "grep 'uses:' in workflows shows 40-hex SHAs; next release page shows attestation and SHA256SUMS."
references:
  owasp_masvs: [MASVS-CODE-3]
  owasp_mastg: []
  other: [CWE-829]
---

# CI actions are pinned to moving major tags, and releases carry no provenance, checksums file or SBOM

## Description
The release job holds the signing keystore secrets and contents:write, yet third-party actions are referenced by mutable tags. A compromised tag of subosito/flutter-action or softprops/action-gh-release would run with access to the keystore. No build attestation, SHA256SUMS or SBOM is attached to the GitHub Release, and the NDK is fetched via sdkmanager without a checksum pin. Mitigation present: tag-vs-pubspec version check, flutter test before build, Flutter version pinned to 3.47.0.

## Expected behaviour
Third-party actions pinned to full commit SHAs; provenance attestation and checksums published.

## Observed behaviour
Tag-pinned actions, no attestation or checksums.

## Recommended remediation
Pin each action to a commit SHA (Dependabot can bump them), add actions/attest-build-provenance and a SHA256SUMS asset, optionally generate a CycloneDX SBOM in CI.

## Verification procedure
grep 'uses:' in workflows shows 40-hex SHAs; next release page shows attestation and SHA256SUMS.

## Fix

All actions in ci.yml and release.yml pinned to full commit SHAs (tag in a comment); releases carry SHA256SUMS.txt. No SBOM/provenance yet.

**Verification pass 2026-10-22 (Phase 22): still open (partial fix) [static].** Partly fixed in 495b258: every action in ci.yml and release.yml is pinned to a 40-hex commit SHA (tag in a comment) and releases carry SHA256SUMS.txt. Still missing: build provenance attestation (actions/attest-build-provenance) and an SBOM. Kept open; downgraded S1 to S0 because the pinning removed the main supply-chain risk.
