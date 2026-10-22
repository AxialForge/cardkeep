# G3 coverage: network security (13), update channel (14), untrusted input

| Domain | Control | State | Basis | Evidence | Finding |
|---|---|---|---|---|---|
| 13 | Cleartext traffic disabled | PASS | artifact | Merged manifest `audit/artifact/manifest-xmltree.txt`: no usesCleartextTraffic, targetSdk 36 (default false) | - |
| 13 | Network security config (no user-CA trust, no debug overrides) | PASS | artifact | No networkSecurityConfig attribute; platform default (system CAs only) | - |
| 13 | All endpoints HTTPS | PASS | static | updater.dart:106 Uri.https; :158 scheme == https | - |
| 13 | Certificate pinning | N/A | static | Public GitHub endpoints, no secrets sent; pinning not warranted | - |
| 13 | No identifiers/PII in requests | PASS | static | updater.dart:107 only Accept + User-Agent headers | - |
| 13 | Timeouts on network calls | PASS | static | updater.dart:109 (12 s), :167 (20 s connect) | MOB-REL-0004 (stream errors) |
| 14 | Update host allow-list | PASS | static | updater.dart:157-159 | - |
| 14 | Update integrity (SHA-256) | PARTIAL | static | updater.dart:149, 161, 185-190 size-only fallback | MOB-API-0001 |
| 14 | Download size limit | FAIL | static | updater.dart:173-177 unbounded | MOB-API-0001 |
| 14 | Redirect handling | PASS | static | package:http follows redirects over TLS to GitHub CDN; initial host checked | - |
| 14 | Downgrade / wrong-signer protection | PASS | static | updater.dart:58 newer-only; Android installer enforces same signer + versionCode | - |
| 14 | Draft/prerelease excluded | PASS | static | updater.dart:122-128 | - |
| 14 | Rate-limit handling | PASS | static | updater.dart:114-116 | - |
| 14 | Install path (REQUEST_INSTALL_PACKAGES / open_filex) | PASS | static | updater.dart:197-206; user confirms in system installer | - |
| 14 | Version comparison robustness | PASS | static | updater.dart:15-35 BigInt parts, pre-release ordering | - |
| CODE | vCard reader size cap | PASS | static | vcard_reader.dart:7,14 (1 MB), field truncation :175 | - |
| CODE | MECARD size cap | PASS | static | vcard_reader.dart:79 (8 KB) | - |
| CODE | CSV import complexity / size cap | FAIL | static+test | csv_import.dart:51,71-74; probe 10k rows 105 s | MOB-SEC-0100 |
| CODE | NFC NDEF parsing / link schemes | PASS | static | ndef.dart:193-197 only http(s)/tel accepted; vCard capped | - |
| CODE | QR classification / link warnings | PASS | static | qr_content.dart:15-32 http(s) only; LinkCheck :82-92 (punycode, IP, shortener, userinfo) | - |
| CODE | Backup zip path traversal | PASS | static | backup.dart:123-124 normalize + isWithin | - |
| CODE | Backup zip bomb / size limit | FAIL | static | backup.dart:81,121 full in-memory decode; transfer_screens.dart:289 | MOB-SEC-0102 |
| CODE | Backup manifest trust / DB validation | PARTIAL | static | backup.dart:100-105 vs 121-127 | MOB-SEC-0102 |
| CODE | Backup newer-schema refusal | PASS | static | backup.dart:94-97 | - |
| CODE | OCR parser ReDoS | PARTIAL | test | rules.dart:55,60,203; 50k chars 84 s | MOB-SEC-0101 |
| PLATFORM | .vcf intent handler size cap | PASS | static | MainActivity.kt:65 (1 MB) | - |
| PLATFORM | .vcf intent URI scheme check | FAIL | static | MainActivity.kt:49-55 | MOB-SEC-0006 (G2) |
| PLATFORM | url_launcher dangerous schemes (javascript:, intent:, file:) | PASS | static+test | link_launcher.dart:45-48 forces https://; tel/sms sanitised :50; external app mode | - |
| PLATFORM | url_launcher malformed input handling | FAIL | test | FormatException outside try | MOB-SEC-0103 |
| PLATFORM | Deep links | N/A | artifact | flutter_deeplinking_enabled=false (Appendix A) | - |
| CODE | SQL injection in raw customSelect/customStatement | PASS | static | contacts_repository.dart:21-40 bound vars; FTS via ftsQuery + `?`; duplicates_repository.dart:295 `$table` from code constants only | - |
| CODE | Notification payload trust | PASS | static | payload = person id routed to /contact/<id> (Appendix A); unknown id shows nothing | - |

Counts: PASS 22, PARTIAL 3, FAIL 5 (one is G2's MOB-SEC-0006), N/A 2. Total 32. No WebSearch used.
