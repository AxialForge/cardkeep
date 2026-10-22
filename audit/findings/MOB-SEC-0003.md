---
finding_id: MOB-SEC-0003
audit_domain: 12
platform: android
severity: S1
blockers: []
title: "Camera captures (takePicture files in the cache dir) are read into memory and never deleted"
status: fixed (unverified)
confidence: medium
evidence_basis: static
affected_component: "lib/features/scan/scan_screen.dart:239-240, 254-255; lib/core/transfer/backup.dart:40-44"
affected_version: "0.6.0 (2010) cdcf49d"
description: "CameraController.takePicture() writes a JPEG to the app cache. The code reads the bytes and drops the XFile without deleting the file, so every captured card photo stays as an untracked copy in cache/ until Android clears the cache, including photos of cards the user later deleted. The files are app-private (no exposure to other apps); the impact is retention, and 'delete' not fully deleting. The OCR and region temp files (lib/scan/scan_pipeline.dart:194-221) are deleted in finally blocks. The VACUUM INTO temp copy of the whole database (backup.dart:40-44) is deleted on success but left behind if readAsBytes throws, because there is no try/finally."
expected_behavior: "The capture file is deleted once its bytes are read; the VACUUM temp is removed on every path."
observed_behavior: "No delete of shot.path; backup temp delete only on the success path."
evidence:
  - "lib/features/scan/scan_screen.dart:239-240 final shot = await c.takePicture(); worker.add(ScanJob(await shot.readAsBytes(), ...))"
  - "lib/features/scan/scan_screen.dart:254-255 same pattern for single capture"
  - "lib/core/transfer/backup.dart:42-44 VACUUM INTO tmp; readAsBytes; tmp.delete() with no finally"
impact:
  privacy: "Photos of deleted contacts' cards may persist in cache."
  user: "Cache growth over many scans."
recommended_remediation: "Delete File(shot.path) in a finally after readAsBytes; wrap backup.dart:42-44 in try/finally."
verification_procedure: "On the phone (camera): capture 3 cards and check app cache size in Settings > Apps > CardKeep > Storage before and after; on a debug build, run-as ls cache/."
references:
  owasp_masvs: [MASVS-STORAGE-2, MASVS-PRIVACY-1]
  owasp_maswe: [MASWE-0002]
  other: [CWE-459]
---

**Fix (unverified).** scan_screen deletes the takePicture cache file right after reading it (_takeBytes); the VACUUM temp is removed in a finally since 0.6.1.
