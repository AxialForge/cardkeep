import 'package:flutter/foundation.dart';

/// What the app is running on, in the few ways that matter here. Tests set
/// [override] instead of the real platform.
enum AppPlatform { android, ios, windows, other }

class PlatformInfo {
  PlatformInfo._();

  /// Set by tests (and nothing else) to pretend to be another platform.
  @visibleForTesting
  static AppPlatform? override;

  static AppPlatform get current {
    final o = override;
    if (o != null) return o;
    if (kIsWeb) return AppPlatform.other;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AppPlatform.android,
      TargetPlatform.iOS => AppPlatform.ios,
      TargetPlatform.windows => AppPlatform.windows,
      _ => AppPlatform.other,
    };
  }

  /// The Windows app (the one that syncs with the phone).
  static bool get isDesktop => current == AppPlatform.windows;
  static bool get isAndroid => current == AppPlatform.android;
  static bool get isPhone => current == AppPlatform.android || current == AppPlatform.ios;

  /// Scanning needs the camera and on-phone text reading (ML Kit): phones only.
  static bool get canScan => isPhone;

  /// Tap cards need an NFC reader.
  static bool get canTap => isAndroid;

  /// The app lock and hide-in-recents rely on the phone's own screen lock.
  static bool get hasPhoneLock => isPhone;

  /// Reminders and the self-updating APK are phone features.
  static bool get hasReminders => isAndroid;
  static bool get canSelfUpdate => isAndroid;
}
