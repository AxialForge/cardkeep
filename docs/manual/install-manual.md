# CardKeep Install Manual

**Version 0.6.2 · Android 7.0 (API 24) or newer · October 2026**

CardKeep is installed from its GitHub Releases page as an APK file. It is not on Google Play yet. Part A covers
installing and looking after the app on a phone; Part B covers building it from source.

## Part A: On your phone

### 1. Pick the right file

Open **github.com/AxialForge/cardkeep/releases/latest** on the phone. Each release lists:

| File | Use it for |
|---|---|
| `CardKeep-<version>-arm64-v8a.apk` | Almost every phone from the last several years. **Pick this one.** |
| `CardKeep-<version>-armeabi-v7a.apk` | Older 32-bit phones only. |
| `CardKeep-<version>-x86_64.apk` | Emulators and x86 devices, not phones. |
| `SHA256SUMS.txt` | Checksums to confirm the APK downloaded intact (optional, see step 4). |
| `CardKeep-<version>-symbols.zip`, `-mapping.txt` | For the developer, to decode crash reports. Not needed to install. |

Not sure which phone you have? Install arm64-v8a; if Android says the app is not compatible, use armeabi-v7a.

### 2. Allow installing from your browser

Android only installs apps from outside Google Play from apps you allow.

1. Tap the downloaded APK (in the browser's downloads or the Files app).
2. Android says the browser (or Files) is not allowed to install unknown apps. Tap **Settings**.
3. Turn on **Allow from this source**, then go back.

This permission applies to that one app (your browser or Files). You can turn it off again after installing.

### 3. Install and open

1. Tap **Install**. Google Play Protect may ask to scan the app: **Scan app** is fine. It may say the app is unknown
   because it is not on Play; choose **Install anyway** (or *More details* → *Install anyway*).
2. Tap **Open**, or find **CardKeep** in your app list.
3. On first use CardKeep asks for the **camera** (choose *While using the app*) when you scan, and for
   **notifications** so follow-up reminders can arrive. Both are optional: without the camera you can pick card
   photos; without notifications there are no reminders.

### 4. Optional: check the download

On a computer, download the APK and `SHA256SUMS.txt` from the same release, then compare:

```
certutil -hashfile CardKeep-0.6.2-arm64-v8a.apk SHA256
```

The printed value must match the line for that file in `SHA256SUMS.txt`. On macOS or Linux use `shasum -a 256`.

### 5. Updating

- **From inside CardKeep:** Settings → **Updates** → **Check for updates**. It shows what's new, downloads the new
  APK, checks it against the checksum GitHub lists, and asks Android to install it over the old one. The first time,
  Android asks to allow CardKeep to install apps: allow it the same way as in step 2.
- **By hand:** install the newer APK from the release page. There is no need to uninstall first.

Updates keep your contacts. Optionally turn on *Check at startup* (off by default); it is the only time CardKeep goes
online on its own.

**Signing:** every release is signed with the same key. If Android ever says "App not installed" or "package
conflicts" when updating, the APK was not from the official release page; uninstalling would delete your data, so make
a backup first (step 6).

### 6. Back up before reinstalling or changing phones

CardKeep is **excluded from Android's cloud backup and device-to-device transfer**: moving to a new phone does not
bring your contacts along by itself, and uninstalling deletes them.

1. Menu → **Export and backup** → **Back up now** → **Save to...** Google Drive, a computer or a memory card.
2. On the new phone (or after reinstalling), install CardKeep, then Menu → **Import** → **CardKeep backup (.zip)**,
   or Export and backup → **Restore from a backup file...**
3. Close and reopen CardKeep. The restore runs at start and tells you how it went.

### 7. Uninstalling

Android Settings → Apps → CardKeep → **Uninstall**, or long-press the icon → *Uninstall*. This deletes every contact,
card photo, backup kept on the phone and setting. Make a backup first if you might want them back.

### 8. Permissions CardKeep uses

| Permission | Why |
|---|---|
| Camera | Scanning cards. Asked the first time you scan. |
| NFC | Reading tap cards. Optional: phones without NFC still install CardKeep. |
| Internet | Only for checking and downloading updates. |
| Install other apps | Installing an update you downloaded inside CardKeep. |
| Notifications | Follow-up reminders. Asked once. |
| Run at startup | Re-scheduling reminders after the phone restarts. |

CardKeep does not ask for contacts, location, microphone, or access to your photos and files: photos and files are
picked through Android's own picker, which shares only what you choose.

## Part B: Building from source

For developers. The repository is public: **github.com/AxialForge/cardkeep**.

### Requirements

- Flutter 3.47 (Dart 3.x), Android SDK and an Android NDK, JDK 17 (Flutter's bundled JDK is fine), CMake and Ninja
  (OpenCV is built from source by `dartcv4`).
- Windows notes: set the SDK and NDK paths explicitly, or the OpenCV build fails with
  "No Android NDK candidates found":

```
$env:ANDROID_HOME = 'C:\Android\sdk'
$env:ANDROID_NDK_HOME = 'C:\Android\sdk\ndk\<version>'
$env:JAVA_TOOL_OPTIONS = '-Djdk.net.unixdomain.tmpdir=C:/tmpj'
```

The last line avoids JDK 25's "Unable to establish loopback connection" Gradle error.

### Build and test

```
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter run
```

### Release builds and signing

- Release builds need `android/key.properties` (git-ignored) pointing at the release keystore:

```
storeFile=upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

- Without it a release build **stops** instead of quietly using the debug key. For a throwaway local test build set
  `CARDKEEP_DEBUG_SIGNING=1`.
- APKs are signed with v2 and v3 signatures (v3 allows rotating the key later with `apksigner rotate`).
- **Back up the keystore and its passwords off the PC.** Losing it means installed copies can never be updated.

```
flutter build apk --release --split-per-abi
```

### Publishing a release

Versions live in `pubspec.yaml` (`version: X.Y.Z+N`). Update `CHANGELOG.md` in the same commit, tag `vX.Y.Z` and
push the tag. The Release workflow builds the three APKs and attaches them, with `SHA256SUMS.txt`, the R8
`mapping.txt` and the Dart `symbols.zip`, to a GitHub Release. Never upload an APK by hand.

To decode a crash stack trace from a release build:

```
flutter symbolize -i trace.txt -d symbols/app.android-arm64.symbols
```
