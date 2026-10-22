---
finding_id: MOB-STORE-0001
audit_domain: 23
platform: android
severity: S3
blockers: [store]
title: "In-app APK self-updater and REQUEST_INSTALL_PACKAGES are not allowed in a Play build"
status: open
confidence: high
evidence_basis: artifact
affected_component: "lib/core/update/updater.dart; android/app/src/main/AndroidManifest.xml:9"
affected_screen: "Settings > Updates"
affected_version: "0.6.0 (versionCode 2010), commit cdcf49d"
description: "The shipped manifest declares android.permission.REQUEST_INSTALL_PACKAGES and the app downloads and installs APKs from GitHub Releases. Play's REQUEST_INSTALL_PACKAGES policy permits the permission only where sending/receiving packages is core functionality (browsers, file managers, backup, MDM and similar), and its FAQ says the policy exists to stop apps that self-update by any method other than Google Play's update mechanism; the Device and Network Abuse policy says the same. A Play upload with this code would be rejected or later removed. Only matters for Play: for GitHub distribution the user-started updater is the intended update path."
expected_behavior: "Play build contains no self-update code and no REQUEST_INSTALL_PACKAGES."
observed_behavior: "manifest-xmltree.txt line 21 declares REQUEST_INSTALL_PACKAGES; updater present in lib/core/update."
evidence:
  - "audit/artifact/manifest-xmltree.txt uses-permission line=21"
  - "android/app/src/main/AndroidManifest.xml:9"
  - "docs/ROADMAP.md S17.9 (play flavour without self-update code) still open"
impact:
  user: "None on GitHub builds."
  business: "Play rejection or removal; possible policy strike on the developer account."
root_cause: "One build flavour serves sideload distribution."
recommended_remediation: "Implement S17.9: a 'play' product flavour (or compile-time define) that excludes the updater UI and code, with a manifest overlay using tools:node=\"remove\" on REQUEST_INSTALL_PACKAGES (and any provider used only for APK install). Keep the GitHub flavour unchanged."
verification_procedure: "aapt2 dump xmltree of the Play AAB base manifest shows no REQUEST_INSTALL_PACKAGES; Settings in the Play build has no Updates section; no request to api.github.com in a network capture."
references:
  google_requirement: "Google Play REQUEST_INSTALL_PACKAGES policy and Device and Network Abuse policy, checked 2026-10-21: https://support.google.com/googleplay/android-developer/answer/12085295 ; https://support.google.com/googleplay/android-developer/answer/9888379"
---
Blocks Play submission only. Fine for GitHub Releases.
