---
finding_id: MOB-PERF-0001
audit_domain: 09
platform: android
severity: S0
blockers: []
title: About 80 MB of memory stays allocated after leaving the Scan screen
status: open
confidence: medium
evidence_basis: runtime
affected_component: Scan screen / camera + ML Kit + opencv_dart lifetime
affected_screen: Scan
affected_version: 0.6.0 (2010) cdcf49d
---

**Description.** Total PSS rose from 86.9 MB (idle on Contacts) to 182.7 MB with the Scan screen open (native heap 25.8 MB -> 99.2 MB). After closing Scan and visiting eleven other screens, PSS stayed at 165-167 MB. It is likely the ML Kit text/barcode recognizers and OpenCV buffers held by long-lived providers rather than a growing leak (it did not grow further), so S0. On low-RAM devices (minSdk 24 phones with 2-3 GB) this raises the chance the app is killed in the background.

**Evidence.**
```
idle (Contacts)          TOTAL PSS:  86891 KB   Native Heap 25836 KB
Scan open                TOTAL PSS: 182749 KB   Native Heap 99196 KB
5 s after closing Scan   TOTAL PSS: 167490 KB
after 11 more screens    TOTAL PSS: 165847 KB
```
(`adb shell dumpsys meminfo com.axialforge.cardkeep`). Screenshot `audit/artifact/screens/13_scan.png`.

**Impact.** User: slightly higher background-kill risk on low-memory phones.
**Recommended remediation.** Close recognizers / release OpenCV mats when the Scan route is disposed (autoDispose providers), and re-check with repeated open/close cycles.
**Verification procedure.** Open/close Scan 5 times; PSS returns to within ~20 MB of idle and does not climb.

**References.** Android "Manage your app's memory", checked 2026-10-21.
