---
finding_id: MOB-SEC-0001
audit_domain: 12
platform: android
severity: S2
blockers: []
title: "Backup scope is undeclared: allowBackup defaults to true with no dataExtractionRules, so the contacts DB, card photos and weekly backup zips go to Google cloud backup and device transfer"
status: open
confidence: high
evidence_basis: artifact
affected_component: "android/app/src/main/AndroidManifest.xml:16-20 <application> (no allowBackup / dataExtractionRules / fullBackupContent)"
affected_version: "0.6.0 (2010) cdcf49d"
description: "The merged release manifest has no android:allowBackup, android:dataExtractionRules or android:fullBackupContent, so the default allowBackup=true applies. Android Auto Backup then includes app_flutter/card_organizer.sqlite, app_flutter/cards/** and app_flutter/backups/*.zip in the user's Google Drive backup (end-to-end encrypted only when a screen lock is set) and in device-to-device transfer. adb backup is already blocked on Android 12+ for targetSdk 31+ (target is 36), so the exposure is cloud and device transfer, not adb. Rated S2: contact PII leaves the device under Google's control without a deliberate, documented decision, and the Data Safety and privacy wording depend on it. It is not a direct attacker exposure."
expected_behavior: "Backup scope is an explicit decision: either allowBackup=false, or dataExtractionRules/fullBackupContent that include or exclude the DB, images and auto-backup zips on purpose, and the privacy text says so."
observed_behavior: "Defaults apply. Nothing is declared."
evidence:
  - "audit/artifact/manifest-xmltree.txt:101-106 application element has label, icon, name, extractNativeLibs, roundIcon, appComponentFactory only; no allowBackup (0x01010280) attribute"
  - "android/app/src/main/AndroidManifest.xml:16-20 application tag; no android/app/src/main/res/xml directory exists"
  - "lib/core/transfer/backup.dart:36 autoDir = app_flutter/backups (weekly full backups inside the backed-up area)"
impact:
  privacy: "Contact PII and card photos copied to Google cloud backup by default."
  user: "Weekly backup zips (up to 4) can push the app over the 25 MB Auto Backup quota, after which cloud backup silently stops."
  business: "Data Safety / privacy statements that say 'stays on your phone' would be inaccurate."
root_cause: "Flutter template default kept."
recommended_remediation: "Declare it. Recommended: keep allowBackup=true but add dataExtractionRules (API 31+) and fullBackupContent (API 24-30) that include the database and cards/ and exclude backups/, restore_pending/, before_restore/ and cache; or set allowBackup=false if the app's own backup is the only supported path. Reflect the choice in the privacy policy and Data Safety."
verification_procedure: "aapt2 dump xmltree of the new APK shows the attributes; on the emulator run 'adb shell bmgr backupnow com.axialforge.cardkeep' with the local transport and inspect the included files."
references:
  owasp_masvs: [MASVS-STORAGE-2, MASVS-PRIVACY-1]
  owasp_maswe: [MASWE-0004]
  owasp_mastg: [MASTG-TEST-0009, MASTG-TEST-0262]
  google_requirement: "Android Auto Backup documentation and Play Data safety form, checked 2026-10-21"
  other: [CWE-530]
---
