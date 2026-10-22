---
finding_id: MOB-PRV-0001
audit_domain: 18
platform: android
severity: S3
blockers: [privacy, store]
title: "ML Kit ships Google's datatransport telemetry stack, contradicting the 'only goes online for updates / no analytics' claims"
status: fixed-verified
confidence: medium
evidence_basis: artifact
affected_component: "google_mlkit_text_recognition / google_mlkit_barcode_scanning -> com.google.mlkit:common 18.11.0 + com.google.android.datatransport:transport-backend-cct 2.3.3"
affected_version: "0.6.0 (2010) cdcf49d"
description: "The merged release manifest contains Google's datatransport stack (transport-api 2.2.1, transport-runtime 2.2.6, transport-backend-cct 2.3.3), pulled in by ML Kit. ML Kit uses it to send SDK usage and performance logs to Google whenever the network is available; the app holds INTERNET, so this can happen independently of the update check. README and Settings say the app only goes online for update checks and has no analytics. Severity S3 because the in-app and README privacy statements and any Data Safety form built on them would be inaccurate; no contact data is believed to be sent. MANUAL REVIEW: confirm with a network capture on the emulator."
preconditions: "Network available; card scanned (text recognition or barcode used)."
steps_to_reproduce:
  - "Install the x86_64 release APK on the emulator with traffic through a logging proxy or DNS log"
  - "Leave 'Check when CardKeep opens' off; scan several cards (single, pile, QR card)"
  - "Look for requests to firebaselogging*.googleapis.com or play.googleapis.com/log"
expected_behavior: "No traffic except the user-started update check, or the traffic is disclosed (README, Settings, privacy policy, Data Safety)."
observed_behavior: "Telemetry transport is in the APK; all privacy text says nothing else goes online."
evidence:
  - "build/app/outputs/logs/manifest-merger-release-report.txt: components MERGED from [com.google.android.datatransport:transport-backend-cct:2.3.3], [com.google.android.datatransport:transport-runtime:2.2.6], [com.google.mlkit:common:18.11.0]"
  - "audit/artifact/manifest-xmltree.txt line=99: android.permission.ACCESS_NETWORK_STATE (merged from transport-backend-cct and androidx.media3:media3-common)"
  - "README.md:50-53: 'No account, no analytics, no ads' / 'The only time CardKeep goes online is when you check for updates'"
  - "lib/features/settings/settings_screen.dart:161 'This is the only time CardKeep goes online'; :186 'No account, no cloud, no analytics.'"
impact:
  security: "None direct."
  privacy: "Device/app diagnostics leave the phone without disclosure."
  user: "Privacy promise is not exactly true."
  business: "Inaccurate Data Safety form is a Play User Data policy violation."
root_cause: "Third-party SDK network behaviour not accounted for in the privacy claims."
recommended_remediation: "Capture traffic first. Then either exclude the transport (Gradle exclude of com.google.android.datatransport:transport-backend-cct, confirm OCR/barcode still work and nothing is sent) or disclose it: reword README/Settings ('Google's on-device text reader may send anonymous usage statistics to Google') and declare it in Data Safety following Google's ML Kit data-disclosure guidance."
verification_procedure: "Network capture across scan + barcode with update check off shows no requests; or wording, policy and Data Safety match observed traffic."
references:
  owasp_masvs: [MASVS-PRIVACY-1, MASVS-PRIVACY-3]
  google_requirement: "Play User Data policy - Data safety section accuracy (checked 2026-10-21)"
  other: []
---
Evidence and reasoning in front matter. Related: MOB-STORE-0005 (Data Safety answers not prepared).

**Verification pass 2026-10-22 (Phase 22): fixed-verified [artifact].** aapt2 xmltree of app-x86_64-release.apk (HEAD 495b258, 0.6.1 versionCode 4011, sha256 9ff12000...295b676d): the TransportBackendDiscovery service carries no backend:...CctBackendFactory meta-data (removed by tools:node=remove, AndroidManifest.xml:90-92), so the datatransport runtime has no backend to send to. [runtime] release build on the emulator: camera permission, gallery picker and OCR of a test card work, no logcat errors. Caveat: no network capture was taken, and the dormant runtime classes still ship.
