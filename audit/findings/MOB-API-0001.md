---
finding_id: MOB-API-0001
audit_domain: 14
platform: android
severity: S1
blockers: []
title: "Update download falls back to a size-only check when GitHub lists no SHA-256 digest, and has no maximum size"
status: fixed (unverified)
confidence: high
evidence_basis: static
affected_component: "lib/core/update/updater.dart:149-150, 161-163, 169-191"
affected_screen: "Settings > Updates"
affected_version: "0.6.0 (versionCode 2010) cdcf49d"
description: "APK integrity uses the GitHub asset 'digest' (sha256) when present; if it is absent but 'size' is present, only the byte count is compared (161, 181). The stream is written to disk with no upper bound (173-177); size is checked only after the full download. Mitigations that keep severity low: HTTPS only and a host allow-list on the asset URL (157-158; GitHub's redirect to its asset CDN is followed by package:http over TLS), release metadata fetched over TLS from api.github.com, and Android's installer refuses an update signed by a different key or with a lower versionCode, so neither a substituted APK nor a downgrade can replace the installed app. Drafts and prereleases are excluded and an update is offered only when newer than installed (58, 122-128), so no downgrade is offered. 403/429 rate limits are handled (114-116). The asset name's version is not cross-checked against the tag."
expected_behavior: "Require the sha256 digest (refuse when missing) and abort once bytes exceed the advertised size or a hard cap (e.g. 150 MB)."
observed_behavior: "Size-only fallback; unbounded write."
evidence:
  - "updater.dart:161 refuses only when BOTH sha256 and size are missing"
  - "updater.dart:173-177 no byte cap inside the loop"
  - "updater.dart:157-158 https + host allow-list"
  - "updater.dart:122-128 draft/prerelease filtered; :58 newer-only"
impact:
  security: "Low: TLS and Android signature verification are the real protections."
  user: "A wrong or oversized response could fill cache storage before being rejected."
recommended_remediation: "Refuse when the digest is missing (current GitHub assets carry one); stop and delete once got > assetBytes; optionally verify the APK signer certificate before install."
verification_procedure: "Unit test with a fake client: missing digest refused; stream longer than size aborted early."
references:
  owasp_masvs: [MASVS-NETWORK-1, MASVS-CODE-2]
  other: [CWE-494, CWE-354]
---

**Fix (unverified).** download() requires the GitHub SHA-256 digest (no size-only fallback) and refuses files over 200 MB, also checked while streaming.
