---
finding_id: MOB-SEC-0100
audit_domain: 13
platform: android
severity: S2
blockers: [quality]
title: "CSV import is quadratic: the separator is re-detected by splitting the whole file at every comma, so a few-thousand-row CSV freezes the app"
status: open
confidence: high
evidence_basis: static
affected_component: "lib/core/transfer/csv_import.dart:51 (case ',' || ';' when _sep(s) == ch) and :71-74 (_sep splits the whole text)"
affected_screen: "Import > CSV"
affected_version: "0.6.0 (versionCode 2010) cdcf49d"
description: "parseCsv calls _sep(s) for every comma or semicolon outside quotes, and _sep runs s.split('\n').first over the entire input each time, so cost is O(separators x file size). The parse runs on the UI isolate (transfer_screens.dart:370) and CSV files have no size cap. Any picked file can freeze the app, and ordinary exports of a few thousand contacts do too. S2: availability and quality only, no data exposure."
preconditions: "User picks a CSV of a few hundred KB or more."
steps_to_reproduce:
  - "Import > CSV, pick a 5,000-row contact export (~400 KB)"
  - "The app freezes ~25 s (10,000 rows ~105 s) before the mapping screen"
expected_behavior: "Linear parse; large files parsed off the UI thread or refused above a cap."
observed_behavior: "Probe (temporary flutter test on host, since deleted): 1,000 rows / 79 KB = 703 ms; 5,000 rows / 395 KB = 25,377 ms; 10,000 rows / 790 KB = 105,406 ms; 200,000 rows did not finish in 6 min."
evidence:
  - "lib/core/transfer/csv_import.dart:51 and :71-74"
  - "lib/features/transfer/transfer_screens.dart:370 parseCsv(utf8.decode(await f.single.readAsBytes(), ...)) - no size limit, main isolate"
  - "probe output above"
impact:
  security: "Local DoS from a crafted or oversized file (user must pick it)."
  user: "App appears hung on large but legitimate CSV exports (ANR risk)."
root_cause: "Separator detection placed inside the per-character loop."
recommended_remediation: "Compute the separator once before the loop; cap input size (e.g. 5 MB) and run parseCsv in compute()."
verification_procedure: "Unit test: a 10,000-row CSV parses in under 500 ms; an oversized file shows a message."
references:
  owasp_masvs: [MASVS-CODE-4]
  other: [CWE-407, CWE-400]
---
