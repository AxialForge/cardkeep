---
finding_id: MOB-STORE-0003
audit_domain: 23
platform: android
severity: S2
blockers: [store]
title: "CI builds split APKs only; no AAB and no Play App Signing setup"
status: open
confidence: high
evidence_basis: static
affected_component: ".github/workflows/release.yml:49 (flutter build apk --release --split-per-abi)"
affected_version: "0.6.0 (versionCode 2010), commit cdcf49d"
description: "New Play apps must be uploaded as Android App Bundles and use Play App Signing. The release workflow only produces per-ABI APKs (ROADMAP S17.9 open). Whether Play installs and GitHub installs should be update-compatible depends on the app signing key chosen at enrollment, which cannot be changed later. Only matters for Play."
expected_behavior: "CI produces an upload-signed AAB for the play flavour."
observed_behavior: "Only CardKeep-<version>-<abi>.apk release assets."
evidence:
  - ".github/workflows/release.yml:49-64"
  - "docs/ROADMAP.md S17.9"
impact:
  business: "Cannot submit to Play."
recommended_remediation: "Add a flutter build appbundle --release job for the play flavour; enroll in Play App Signing, deciding first whether to reuse the AxialForge key (keeps sideload and Play builds interchangeable) or a Google-generated key."
verification_procedure: "Release run produces app-play-release.aab; bundletool validate passes; Play Console internal test upload accepted."
references:
  google_requirement: "Android App Bundle requirement and Play App Signing, checked 2026-10-21: https://developer.android.com/guide/app-bundle ; https://support.google.com/googleplay/android-developer/answer/9842756"
---
