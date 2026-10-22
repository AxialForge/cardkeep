# G1 coverage: build integrity (02), install/upgrade/removal (03), dependencies and supply chain (18)

Audited artifact: CardKeep-0.6.0-arm64-v8a.apk (v0.6.0, cdcf49d). Tools: aapt2/apksigner/zipalign 36.0.0. Date 2026-10-21.
Note: the brief listed "21 Dependencies/SBOM"; in domains.md that control set is domain 18 (21 is logging). Covered as 18.

| Domain | Control | State | Basis | Evidence | Finding |
|---|---|---|---|---|---|
| 02 | debuggable off in release | PASS | artifact | manifest-xmltree.txt: no android:debuggable attribute | - |
| 02 | Debug endpoints, test credentials, dev menus, mock services, staging URLs absent | PASS | static | Only outbound host api.github.com (updater.dart:106); no staging host found; Appendix A outbound table | - |
| 02 | Test ad IDs absent | N/A | static | No ads SDK in pubspec.lock | - |
| 02 | Verbose logging off | NOT TESTED | - | Logcat review belongs to logging domain 21 auditor | - |
| 02 | Dev certs removed / no user-CA trust | PASS | artifact | No networkSecurityConfig, no cleartext flag; defaults (no user CA for targetSdk 36) | - |
| 02 | Signing config correct, dev/prod keys separated | PASS-WARN | artifact | apksigner: verifies, 1 signer, cert matches prior releases (Appendix A); debug-key fallback in build.gradle.kts:47 | MOB-BLD-0002 |
| 02 | Signing scheme | PASS-WARN | artifact | v2 true, v3 false | MOB-BLD-0005 |
| 02 | Package ID and versioning correct | PASS | artifact | badging: com.axialforge.cardkeep 0.6.0; pubspec 0.6.0+10; release.yml tag-vs-pubspec check | - |
| 02 | versionCode scheme across ABI splits monotonic | PASS | artifact | arm64 2010 = 2000+10 (Flutter split offsets 1000/2000/4000 x 1 + build); build number increments per release | - |
| 02 | Optimization / minification on | PASS | static | release uses proguard-android-optimize + proguard-rules.pro (Flutter enables R8 for release); ML Kit keep rules present | - |
| 02 | Symbols / mapping archived, not shipped | PASS-WARN | artifact | not shipped (unzip -l); not archived either | MOB-BLD-0004 |
| 02 | No secrets, .env, API keys, private keys in package | PASS | artifact | unzip -l: no .env/.pem/keystore; strings scan for private-key / AIza / ghp_ patterns: no hits | - |
| 02 | No secrets in repo / CI | PASS | static | git ls-files: no jks/keystore/key.properties/.env; .gitignore:55-63 and android/.gitignore:78-80 ignore them; CI uses secrets.* only | - |
| 02 | No unused permissions | FAIL | artifact | RECORD_AUDIO, READ_MEDIA_VIDEO, READ_MEDIA_AUDIO merged in | MOB-BLD-0001 |
| 02 | No unused assets | NOT TESTED | - | Asset-by-asset usage not traced; APK 362 entries, 53.4 MB mostly native libs | - |
| 02 | APK inventory | PASS | artifact | native-libs.txt (libapp, libflutter, libdartcv, ML Kit OCR + barhopper, libsqlite3); zipalign -c -P 16 OK; extractNativeLibs=false | - |
| 02 | Lockfiles committed | PASS | static | pubspec.lock tracked in git | - |
| 02 | Reproducible / provenance-tracked CI build | PASS-WARN | static | Built by release.yml on tag, Flutter pinned 3.47.0; no attestation; byte-for-byte rebuild not attempted | MOB-BLD-0003 |
| 02 | Reproducibility rebuild comparison | NOT TESTED | - | Local OpenCV/NDK rebuild not run in this audit | - |
| 02 | Signing-key protection and backup | MANUAL REVIEW | static | keys/ git-ignored, keystore only in GitHub secrets; offline backup location not documented | MOB-BLD-0005 |
| 02 | Rollback artifact retained | PASS | artifact | Previous APKs remain on GitHub Releases; same key allows reinstall only after uninstall (downgrade blocked by versionCode) | - |
| 03 | Fresh install -> launch -> init | NOT TESTED | - | Runtime install flow owned by functional/runtime auditor on emulator | - |
| 03 | Auth / configure | N/A | - | No accounts (Appendix A) | - |
| 03 | Upgrade previous release -> candidate: DB schema migration | PASS | static | database.dart:32 schemaVersion 3; onUpgrade:47-53 adds table (from<2) and columns (from<3), additive only | - |
| 03 | Upgrade: prefs, caches, user files retained | PASS | static | Same applicationId and signing key; card files in app_flutter/cards untouched by migration | - |
| 03 | Upgrade path via in-app updater integrity | PASS-WARN | static | updater.dart:157-160 https + GitHub host allow-list; :161-163 refuses when neither SHA-256 nor size known; :185-187 SHA-256 check; size-only when digest absent; Android verifies same signer | - |
| 03 | Failed-migration recovery | MANUAL REVIEW | static | No try/rollback around onUpgrade; drift runs it in a transaction; pre-restore copy exists only for restore (CLAUDE.md:121) | - |
| 03 | Encryption migration / credentials retained | N/A | - | No encryption or tokens | - |
| 03 | Upgrade after inactivity, large data, near-full storage | NOT TESTED | - | Runtime only | - |
| 03 | Removal / reinstall: what persists (cloud backup, shared storage) | FAIL | artifact | Auto Backup default on; exports written via SAF/share persist by design | MOB-AND-0001 |
| 03 | Keystore / device IDs / auth state persistence | N/A | - | None used | - |
| 18 | Inventory SDKs, native libs, packages incl. transitive | PASS | static | audit/B-sbom.md from pubspec.lock + native-libs.txt | - |
| 18 | Versions and age (outdated) | PASS-WARN | static | `flutter pub outdated` 2026-10-21: direct go_router 18.1.0->18.1.1, ndef_record 1.4.2 (1.5.0 not resolvable); 21 transitive behind, incl. sqlite3 3.5.2->3.7.1, dartcv4 2.2.2->2.3.1 | - |
| 18 | Known vulnerabilities | MANUAL REVIEW | static | No pub.dev advisory surfaced by pub tooling on 2026-10-21; no external CVE DB lookup (OSV/GHSA) done for bundled native SQLite/OpenCV versions | - |
| 18 | Licences | PASS | static | All BSD/MIT/Apache-2.0 for shipped code; dbus MPL-2.0 is Linux-only (not in APK); ML Kit under Google ML Kit terms; licences shown via Flutter LicensePage expected | - |
| 18 | Maintainer / deprecation / abandonment | PASS-WARN | static | sqlite3_flutter_libs 0.6.0+eol and sqlcipher_flutter_libs 0.7.0+eol are end-of-life stub packages (native lib now via sqlite3 build hooks); remove when drift_flutter allows | - |
| 18 | Ad / analytics / auth / crypto libraries | PASS | static | None besides crypto (SHA-256); firebase-components present only as ML Kit internals, no Firebase services | - |
| 18 | Necessity | PASS | static | Every direct dependency maps to a feature in Appendix A stack | - |
| 18 | SBOM (CycloneDX/SPDX) | PASS-WARN | static | Table SBOM produced (B-sbom.md); no machine-readable SBOM in CI | MOB-BLD-0003 |
| 18 | Lockfile integrity and pinned versions | PASS | static | pubspec.lock committed with sha256 per hosted package; CI runs pub get against it | - |
| 18 | CI supply chain (action pinning) | FAIL | static | Actions pinned by major tag | MOB-BLD-0003 |

Counts: PASS 18, PASS-WARN 8, FAIL 3, MANUAL REVIEW 3, NOT TESTED 5, N/A 4, BLOCKED 0 (total 41).
