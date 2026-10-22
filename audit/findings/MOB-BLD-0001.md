---
finding_id: MOB-BLD-0001
audit_domain: 2
platform: android
severity: S2
blockers: [store]
title: "Shipped APK declares RECORD_AUDIO, READ_MEDIA_VIDEO and READ_MEDIA_AUDIO that the app never uses"
status: duplicate (tracked as MOB-STORE-0002)
confidence: medium
evidence_basis: artifact
affected_component: "merged manifest (from plugin manifests, likely camera / image_picker / file_picker); no tools:node=remove in android/app/src/main/AndroidManifest.xml"
affected_version: "0.6.0 (versionCode 2010 arm64), commit cdcf49d"
evidence:
  - "audit/artifact/manifest-xmltree.txt:74-75 uses-permission RECORD_AUDIO (manifest line 82)"
  - "audit/artifact/manifest-xmltree.txt:86-89 READ_MEDIA_VIDEO, READ_MEDIA_AUDIO"
  - "android/app/src/main/AndroidManifest.xml:2-12 declares only CAMERA, NFC, INTERNET, REQUEST_INSTALL_PACKAGES, POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED"
recommended_remediation: "Add uses-permission entries with tools:node='remove' for RECORD_AUDIO, READ_MEDIA_VIDEO, READ_MEDIA_AUDIO (and READ_MEDIA_IMAGES if only the system photo picker is used); construct CameraController with enableAudio: false; re-test capture and gallery import."
verification_procedure: "aapt2 dump permissions on the new APK lists none of the removed permissions; capture and gallery import still work on the emulator."
references:
  owasp_masvs: [MASVS-PLATFORM-1]
  owasp_mastg: [MASTG-TEST-0024]
  other: ['Google Play Photo and Video Permissions policy (re-check in domain 22)']
---

**Consolidation:** same defect as MOB-STORE-0002; counted there, not here.

# Shipped APK declares RECORD_AUDIO, READ_MEDIA_VIDEO and READ_MEDIA_AUDIO that the app never uses

## Description
The release manifest merges in RECORD_AUDIO (no maxSdkVersion), READ_MEDIA_VIDEO and READ_MEDIA_AUDIO from plugins. CardKeep only takes still card photos and imports .vcf/.csv/.zip through SAF. Unused permissions widen the surface, show on the app's permission page, and READ_MEDIA_* fall under Google Play's Photo and Video Permissions policy when the app moves to Play (M9). Presence is certain; the exact contributing plugin is medium confidence.

## Expected behaviour
Only permissions the app uses ship.

## Observed behaviour
Three unused dangerous permissions ship.

## Recommended remediation
Add uses-permission entries with tools:node="remove" for RECORD_AUDIO, READ_MEDIA_VIDEO, READ_MEDIA_AUDIO (and READ_MEDIA_IMAGES if only the system photo picker is used); construct CameraController with enableAudio: false; re-test capture and gallery import.

## Verification procedure
aapt2 dump permissions on the new APK lists none of the removed permissions; capture and gallery import still work on the emulator.
