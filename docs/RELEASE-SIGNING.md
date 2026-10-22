# Release signing key

Release APKs are signed with the upload key in `android/upload-keystore.jks`
(local, git-ignored) and, in CI, from the `ANDROID_KEYSTORE_B64` secret.

- **Back it up.** Keep a copy of the keystore file and its passwords somewhere
  other than this PC (for example an encrypted USB stick and the password
  manager). Losing it means existing installs can never be updated: Android
  refuses an update signed with a different key.
- **v3 signing is on**, so the key can be rotated later (`apksigner rotate`)
  without breaking updates.
- **No key, no release.** A release build without `android/key.properties`
  stops instead of falling back to the debug key. For a throwaway local test
  build set `CARDKEEP_DEBUG_SIGNING=1`.
- Each GitHub release also carries `SHA256SUMS.txt`, the R8 `mapping.txt` and
  the Dart `symbols.zip` for decoding crash stack traces
  (`flutter symbolize -i <trace> -d <symbols>/app.android-arm64.symbols`).
