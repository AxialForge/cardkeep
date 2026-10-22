---
finding_id: MOB-STORE-0002
audit_domain: 23
platform: android
severity: S3
blockers: [store]
title: "Plugin-merged READ_MEDIA_IMAGES/VIDEO/AUDIO and RECORD_AUDIO are declared but no feature needs them"
status: fixed (unverified)
confidence: medium
evidence_basis: artifact
affected_component: "Merged manifest lines 82-92: RECORD_AUDIO from camera_android; READ_MEDIA_* and legacy storage (maxSdk 32/28) from picker plugins"
affected_version: "0.6.0 (versionCode 2010), commit cdcf49d"
description: "The app's own manifest requests only CAMERA, NFC, INTERNET, REQUEST_INSTALL_PACKAGES, POST_NOTIFICATIONS and RECEIVE_BOOT_COMPLETED. The merged APK also declares RECORD_AUDIO, READ_MEDIA_IMAGES, READ_MEDIA_VIDEO and READ_MEDIA_AUDIO. Play's Photo and Video Permissions policy (mandatory since 2025-05-28) allows READ_MEDIA_IMAGES/VIDEO only for apps whose core function needs broad media access, with a Play Console declaration; an app importing a few card photos is expected to use the system Photo Picker, and apps that do not need the permissions must remove them. RECORD_AUDIO (microphone) has no feature behind it (still photos only) and would show on the install page and need a Data safety explanation. Confidence medium on whether any is requested at runtime (owned by the permissions domain). On GitHub this is a least-privilege issue, not a blocker."
expected_behavior: "Only permissions used by a feature are declared; card-photo import uses the Photo Picker."
observed_behavior: "manifest-xmltree.txt uses-permission lines 82, 90, 91, 92."
evidence:
  - "audit/artifact/manifest-xmltree.txt lines 82-92"
  - "android/app/src/main/AndroidManifest.xml has 6 uses-permission entries"
  - "pub cache camera_android android/src/main/AndroidManifest.xml:5 RECORD_AUDIO"
impact:
  privacy: "Install page and Data safety would show microphone and media access the app does not use."
  business: "Declaration rejection or removal under the Photo and Video Permissions policy."
root_cause: "Manifest merger pulls plugin permissions; no tools:node=remove overrides."
recommended_remediation: "Add uses-permission entries with tools:node=\"remove\" for RECORD_AUDIO, READ_MEDIA_IMAGES, READ_MEDIA_VIDEO, READ_MEDIA_AUDIO (and legacy storage if unused); create the camera controller with enableAudio false; make Import card photos use the Photo Picker. Retest import on API 36 and an API 29 emulator."
verification_procedure: "aapt2 dump permissions on the new build lists none of the removed permissions; Import card photos still works on both emulators."
references:
  google_requirement: "Google Play Photo and Video Permissions policy, checked 2026-10-21: https://support.google.com/googleplay/android-developer/answer/14115180"
---
Blocks Play submission (media permissions); least-privilege improvement for GitHub.

## Fix

tools:node="remove" for RECORD_AUDIO and READ_MEDIA_IMAGES/VIDEO/AUDIO/VISUAL_USER_SELECTED in AndroidManifest.xml; merged release manifest now has none of them. Camera (camerax, no video) and the system photo picker need none.
