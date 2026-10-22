---
finding_id: MOB-AND-0001
audit_domain: 3
platform: android
severity: S2
blockers: [privacy]
title: "Android auto-backup is on by default, so the contacts database and card photos go to Google cloud and device-transfer backups"
status: duplicate (tracked as MOB-SEC-0001)
confidence: high
evidence_basis: artifact
affected_component: "android/app/src/main/AndroidManifest.xml:15-19 (application has no allowBackup / dataExtractionRules / fullBackupContent)"
affected_version: "0.6.0 (versionCode 2010 arm64), commit cdcf49d"
evidence:
  - "grep allowBackup|dataExtraction|fullBackup audit/artifact/manifest-xmltree.txt -> no match"
  - "android/app/src/main/AndroidManifest.xml:15-19 application attributes are label, name, icon, roundIcon only"
  - "No backup or data_extraction_rules XML under android/app/src/main/res"
recommended_remediation: "Add android:allowBackup='false' and a data_extraction_rules.xml that excludes cloud-backup and device-transfer of the database and cards/ (or document the intent if keeping it). Reflect it in the privacy text / Data Safety."
verification_procedure: "Rebuild; manifest-xmltree shows allowBackup=false and dataExtractionRules; `adb shell bmgr backupnow com.axialforge.cardkeep` reports the package not eligible."
references:
  owasp_masvs: [MASVS-STORAGE-2]
  owasp_mastg: [MASTG-TEST-0009]
  other: [CWE-530]
---

**Consolidation:** same defect as MOB-SEC-0001; counted there, not here.

# Android auto-backup is on by default, so the contacts database and card photos go to Google cloud and device-transfer backups

## Description
The merged release manifest does not set android:allowBackup, android:fullBackupContent or android:dataExtractionRules, so the Android default (allowBackup=true) applies. Auto Backup and device-to-device transfer then include app_flutter/card_organizer.sqlite and app_flutter/cards/. The app's own backup design (user-chosen .zip via SAF) implies on-device-only intent, and the threat model lists 'backups reading it' as a main risk. After uninstall and reinstall on a phone signed into the same Google account, data may silently come back; this is not documented. Google cloud backups are end-to-end encrypted with the lock-screen credential on Android 9+, which limits but does not remove the exposure.

## Expected behaviour
Backup behaviour is a deliberate, documented choice: allowBackup=false plus dataExtractionRules excluding the database (Android 12+), or an explicit include list stated in the privacy notes.

## Observed behaviour
Default full Auto Backup of contact PII; reinstall behaviour undocumented.

## Recommended remediation
Add android:allowBackup="false" and a data_extraction_rules.xml that excludes cloud-backup and device-transfer of the database and cards/ (or document the intent if keeping it). Reflect it in the privacy text / Data Safety.

## Verification procedure
Rebuild; manifest-xmltree shows allowBackup=false and dataExtractionRules; `adb shell bmgr backupnow com.axialforge.cardkeep` reports the package not eligible.
