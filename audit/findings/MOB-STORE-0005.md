---
finding_id: MOB-STORE-0005
audit_domain: 23
platform: android
severity: S1
blockers: [store]
title: "Data safety answers not prepared; they depend on the Play build contents"
status: open
confidence: high
evidence_basis: static
affected_component: "Play Console (no app created yet)"
affected_version: "0.6.0 (versionCode 2010), commit cdcf49d"
description: "Every Play app must complete the Data safety section. Expected answers for CardKeep: no data collected or shared (on-device processing only, bundled ML Kit models, no analytics/ads SDKs), deletion by uninstall. What could change this: the GitHub update check (removed in the Play build per MOB-STORE-0001), the planned opt-in link fetch, and any ML Kit telemetry, which must be checked against Google's ML Kit data disclosure for bundled models. No draft exists. Only matters for Play."
recommended_remediation: "Draft the Data safety answers from the final Play AAB's permissions and SDK list, confirm ML Kit disclosure, and keep them consistent with the privacy policy."
verification_procedure: "Draft reviewed against final AAB permissions and a network capture of the Play build showing no outbound traffic in normal use."
references:
  google_requirement: "Google Play Data safety section, checked 2026-10-21: https://support.google.com/googleplay/android-developer/answer/10787469"
---
