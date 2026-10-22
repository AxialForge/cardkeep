---
finding_id: MOB-PRV-0004
audit_domain: 17
platform: android
severity: S1
blockers: []
title: "open_filex and camera_android_camerax also merge legacy READ/WRITE_EXTERNAL_STORAGE that the app never uses"
status: open
confidence: high
evidence_basis: artifact
affected_component: "android/app/src/main/AndroidManifest.xml (no tools:node=\"remove\"); plugins open_filex 5.x, camera_android_camerax 0.7.5+1"
affected_version: "0.6.0 (2010) cdcf49d"
description: "Complements MOB-BLD-0001 / MOB-STORE-0002 (RECORD_AUDIO, READ_MEDIA_*), which do not cover the legacy storage pair or name the source plugins. WRITE_EXTERNAL_STORAGE (maxSdk 28) comes from camera_android_camerax; READ_EXTERNAL_STORAGE (maxSdk 32) and READ_MEDIA_IMAGES/VIDEO/AUDIO come from open_filex, whose only use is opening the downloaded update APK from the app cache (no storage permission needed). On minSdk 24-32 devices the install screen and runtime surface include broad storage access. All app data is app-private and imports/exports go through SAF and the Photo Picker, so none of these are needed."
expected_behavior: "Only CAMERA, NFC, INTERNET, POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED (+ REQUEST_INSTALL_PACKAGES on the GitHub build)."
observed_behavior: "Legacy storage permissions merged."
evidence:
  - "audit/artifact/manifest-xmltree.txt line=83 WRITE_EXTERNAL_STORAGE maxSdkVersion=28; line=86 READ_EXTERNAL_STORAGE maxSdkVersion=32"
  - "build/app/outputs/logs/manifest-merger-release-report.txt: WRITE_EXTERNAL_STORAGE ADDED from [:camera_android_camerax]; READ_EXTERNAL_STORAGE, READ_MEDIA_IMAGES/VIDEO/AUDIO ADDED from [:open_filex]"
  - "lib/core/update/updater.dart:201 OpenFilex.open(apk.path, ...) is the only open_filex call"
impact:
  privacy: "Over-broad permission surface on Android 7-12."
recommended_remediation: "Add tools:node=\"remove\" for READ_EXTERNAL_STORAGE and WRITE_EXTERNAL_STORAGE together with the fix for MOB-BLD-0001/MOB-STORE-0002, or replace open_filex with a FileProvider + ACTION_VIEW intent in MainActivity."
verification_procedure: "aapt2 dump badging on the rebuilt APK shows neither permission; update install still works on an API 28 and API 36 emulator."
references:
  owasp_masvs: [MASVS-PLATFORM-1, MASVS-PRIVACY-1]
---
See front matter.
