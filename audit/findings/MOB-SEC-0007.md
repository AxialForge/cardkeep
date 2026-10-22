---
finding_id: MOB-SEC-0007
audit_domain: 12
platform: android
severity: S0
blockers: []
title: "debugPrint error logging runs in release, and clipboard copies of contact details are not flagged sensitive"
status: fixed (unverified)
confidence: medium
evidence_basis: static
affected_component: "lib/features/scan/scan_screen.dart:260; lib/main.dart:18; lib/scan/scan_pipeline.dart:159,180; lib/features/contacts/contact_detail_screen.dart:418; lib/features/tap/tap_screen.dart:238"
affected_version: "0.6.0 (2010) cdcf49d"
description: "debugPrint is not stripped in release builds. Four sites log exception text (one with a stack trace) to logcat. They log errors, not contact fields, so PII exposure is unlikely, and since Android 4.1 other apps cannot read logcat. Clipboard.setData copies phone, email or tag text without ClipDescription.EXTRA_IS_SENSITIVE, so Android 13+ shows it in the clipboard preview, and keyboards with clipboard history keep it. Copying is user-initiated. Both are informational."
evidence:
  - "lib/features/scan/scan_screen.dart:260 debugPrint('Card read failed: $e\\n$st')"
  - "lib/main.dart:18, lib/scan/scan_pipeline.dart:159,180 debugPrint of exceptions"
  - "lib/features/contacts/contact_detail_screen.dart:418 Clipboard.setData(ClipboardData(text: shown))"
  - "lib/features/tap/tap_screen.dart:238 Clipboard.setData(ClipboardData(text: text))"
recommended_remediation: "Guard the logs with kDebugMode (or keep only the error type); optionally mark clips sensitive through a small platform-channel helper."
references:
  owasp_masvs: [MASVS-STORAGE-2, MASVS-PLATFORM-3]
  owasp_maswe: [MASWE-0001, MASWE-0053]
  other: [CWE-532, CWE-200]
---

## Fix

debugPrint is a no-op in release (main.dart). Contact details are copied through copySensitive (lib/features/shared/sensitive_clipboard.dart) which sets ClipDescription EXTRA_IS_SENSITIVE via MainActivity.
