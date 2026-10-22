---
finding_id: MOB-SEC-0006
audit_domain: 12
platform: android
severity: S1
blockers: []
title: "Incoming vCard intent reads any URI without checking scheme or authority (confused-deputy read of CardKeep's own private files)"
status: open
confidence: medium
evidence_basis: static
affected_component: "android/app/src/main/kotlin/com/axialforge/cardkeep/MainActivity.kt:47-70 readVcf"
affected_version: "0.6.0 (2010) cdcf49d"
description: "MainActivity is exported. readVcf takes intent.data (VIEW) or EXTRA_STREAM (SEND) and opens it with CardKeep's own contentResolver without checking the scheme. Intent filters do not constrain explicit intents, so another app can pass file:///data/user/0/com.axialforge.cardkeep/... or a content URI on one of CardKeep's own non-exported FileProviders. CardKeep then reads its own private file and parses it as a vCard into the Import screen. Nothing is returned to the caller and the import needs user confirmation, so the impact is limited to a confusing or spoofed import, with no exfiltration. The 1 MB cap (line 62) is enforced correctly while streaming. The VIEW filter also carries the BROWSABLE category, which a content: file open does not need."
expected_behavior: "Only content:// URIs from other authorities are accepted; file:// and CardKeep's own authorities are rejected."
observed_behavior: "Any URI is opened."
evidence:
  - "MainActivity.kt:49-53 uri from intent.data or EXTRA_STREAM, no scheme or authority check"
  - "MainActivity.kt:55 contentResolver.openInputStream(uri)"
  - "audit/artifact/manifest-xmltree.txt:107 MainActivity exported=true"
  - "android/app/src/main/AndroidManifest.xml:43-50 VIEW filter with BROWSABLE"
impact:
  security: "Confused-deputy read limited to display inside CardKeep; no data leaves the app."
recommended_remediation: "Require uri.scheme == 'content' and an authority that does not start with packageName; drop BROWSABLE from the VIEW filter."
verification_procedure: "adb shell am start -n com.axialforge.cardkeep/.MainActivity -a android.intent.action.VIEW -d file:///data/user/0/com.axialforge.cardkeep/app_flutter/x.vcf -t text/vcard: the app ignores it."
references:
  owasp_masvs: [MASVS-PLATFORM-1, MASVS-CODE-4]
  owasp_maswe: [MASWE-0066]
  owasp_mastg: [MASTG-TEST-0029]
  other: [CWE-441]
---
