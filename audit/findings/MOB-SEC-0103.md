---
finding_id: MOB-SEC-0103
audit_domain: 13
platform: android
severity: S1
blockers: []
title: "Opening a malformed website value (e.g. 'javascript:alert(1)' from a vCard or QR) throws an uncaught FormatException"
status: fixed (unverified)
confidence: high
evidence_basis: static
affected_component: "lib/core/links/link_launcher.dart:37 web() and :45-48 webUri() (Uri.parse runs outside the try in open())"
affected_screen: "Contact detail > Website"
affected_version: "0.6.0 (versionCode 2010) cdcf49d"
description: "webUri prefixes https:// to anything not starting with http(s)://, which correctly neutralises javascript:, intent:, file: and content: schemes. But Uri.parse('https://javascript:alert(1)') throws FormatException ('Invalid port') before open()'s try/catch, so the tap produces an uncaught async error instead of a message. No security impact; robustness only."
evidence:
  - "probe: LinkLauncher.webUri('javascript:alert(1)') -> FormatException: Invalid port (at character 20)"
  - "link_launcher.dart:13-19 try wraps only _open"
impact:
  user: "Tapping such a website does nothing and logs an error."
recommended_remediation: "Use Uri.tryParse in webUri and return false / show 'Not a valid web address'."
verification_procedure: "Unit test: web('javascript:alert(1)') returns false without throwing."
references:
  owasp_masvs: [MASVS-PLATFORM-1, MASVS-CODE-4]
  other: [CWE-20]
---

**Fix (batch C, 2026-10-22).** webUri uses Uri.tryParse and returns null unless http(s) with a host; web() returns false; edit screen uses web(). Tested.
