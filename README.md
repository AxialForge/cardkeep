# CardKeep

<img src="design/branding/CardKeep-mark-1024.png" width="96" align="right" alt="CardKeep logo">

A business card organizer that keeps everything on your phone. No account, no cloud, no tracking.

**Version 0.1.0** is the first test build: a fast, private address book for the people you meet at work. You can add
contacts by hand, search them by anything (even part of a phone number), call, email, text or look them up on the
web, rate leads, set follow-ups and keep dated notes. Card scanning arrives in 0.2.

## Install (Android)

1. On your phone, open the latest [Release](../../releases) and download `CardKeep-<version>-arm64-v8a.apk`
   (most phones from the last several years). Use `armeabi-v7a` for older 32-bit phones.
2. Open the file and allow installing from your browser or files app when Android asks.
3. Open **CardKeep**.

**Updating:** install a newer APK the same way; it updates in place and keeps your contacts (no need to uninstall).
From version 0.2.0, Settings → Updates → *Check for updates* does this from inside the app.

## Privacy

Your contacts live in one database on the phone. CardKeep has no account, sends no analytics, and does not upload
anything. Links open in your own browser, dialer, mail and maps apps. Later versions add optional LAN sync between
your own devices.

## Plan

See [docs/ROADMAP.md](docs/ROADMAP.md) for every section and milestone, and [CHANGELOG.md](CHANGELOG.md) for what each
version added.

## Building

Flutter 3.47. `flutter pub get`, `dart run build_runner build`, `flutter test`, `flutter run`. Project notes for
contributors are in [CLAUDE.md](CLAUDE.md).
