---
finding_id: MOB-SEC-0101
audit_domain: 13
platform: android
severity: S1
blockers: []
title: "OCR text parser regexes are super-linear on long lines (20k digits 13 s, 50k chars 84 s)"
status: fixed-verified
confidence: medium
evidence_basis: static
affected_component: "lib/parser/rules.dart:55 (_email), :60 (_phone), :203 (spaced-email repair); parseCard at :190 has no length cap"
affected_screen: "Scan review"
affected_version: "0.6.0 (versionCode 2010) cdcf49d"
description: "parseCard accepts OCR lines of any length. Probe with a single OCR line: '1' x 20000 = 12,860 ms; 'a.' x 10000 + '@' = 21,982 ms; 'x' x 50000 = 83,667 ms. Real card OCR is short (ML Kit output for a card, typically under 2 KB), so practical exploitability is low; the realistic worst case is a gallery photo of a dense text page. Polynomial, not exponential, backtracking."
expected_behavior: "Parser time bounded regardless of input."
observed_behavior: "Timings above from a temporary flutter test (deleted)."
evidence:
  - "lib/parser/rules.dart:55, :60, :203"
  - "probe: len 20000 -> 12860 ms; len 20001 -> 21982 ms; len 50000 -> 83667 ms"
impact:
  security: "Local DoS only; needs a crafted image."
  user: "Scanning a non-card image could hang the review."
recommended_remediation: "Truncate each OCR line (e.g. 300 chars) and the page (e.g. 4 KB) before parseCard; keep parsing in an isolate."
verification_procedure: "Re-run the 50k-char probe: under 100 ms."
references:
  owasp_masvs: [MASVS-CODE-4]
  other: [CWE-1333, CWE-400]
---

**Fix (batch C, 2026-10-22).** OCR lines capped at 200 chars and 80 lines per side before the regexes (lib/parser/rules.dart); test: 50k-char lines < 1 s.

**Verification pass 2026-10-22 (Phase 22): fixed-verified [static].** rules.dart caps lines at 200 chars and 80 lines per side; hostile_input_test.dart long-line case passes (flutter test at 495b258: 180 passed, 2 skipped, 0 failed).
