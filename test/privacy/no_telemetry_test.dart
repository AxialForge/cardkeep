import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// S15.12: CardKeep has no analytics, no telemetry and no crash reporting. This
/// fails the build if one of those libraries or services is ever added.
const _banned = [
  'firebase_analytics',
  'firebase_crashlytics',
  'firebase_performance',
  'firebase_core',
  'sentry',
  'sentry_flutter',
  'amplitude',
  'mixpanel',
  'segment',
  'posthog',
  'appcenter',
  'bugsnag',
  'instabug',
  'datadog',
  'newrelic',
  'countly',
  'matomo',
  'flutter_branch_sdk',
  'adjust_sdk',
  'appsflyer',
  'facebook_app_events',
  'google_mobile_ads',
  'onesignal',
  'smartlook',
  'logrocket',
  'clarity',
  'umeng',
];

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final lock = File('pubspec.lock').readAsStringSync();
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('pubspec.yaml lists no analytics, advertising or crash-reporting package', () {
    final deps = RegExp(r'^  ([a-z0-9_]+):', multiLine: true).allMatches(pubspec).map((m) => m.group(1)!).toSet();
    expect(deps.intersection(_banned.toSet()), isEmpty);
  });

  test('pubspec.lock pulls in none of them either, directly or through another package', () {
    final all = RegExp(
      r'^  ([a-z0-9_]+):\n    dependency',
      multiLine: true,
    ).allMatches(lock).map((m) => m.group(1)!).toSet();
    expect(all, isNotEmpty);
    expect(all.intersection(_banned.toSet()), isEmpty);
  });

  test('the Android manifest has no analytics or ads metadata or services', () {
    for (final marker in [
      'com.google.firebase',
      'google_analytics',
      'com.google.android.gms.ads',
      'com.google.android.gms.measurement',
      'crashlytics',
      'sentry',
      'io.sentry',
      'com.facebook',
    ]) {
      expect(manifest.contains(marker), isFalse, reason: 'found "$marker" in AndroidManifest.xml');
    }
  });

  test('the only network use is an update check (a documented, opt-in call to GitHub)', () {
    final hosts = <String>{};
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final m in RegExp(r'''https?://([a-z0-9.\-]+)''').allMatches(f.readAsStringSync())) {
        hosts.add(m.group(1)!);
      }
    }
    // Hosts that appear as links the person taps or as search URLs. None is called by the app itself
    // except api.github.com for the update check.
    const allowed = {
      'api.github.com',
      'github.com',
      'www.google.com',
      'duckduckgo.com',
      'www.bing.com',
      'schemas.android.com',
      'www.w3.org',
      'localhost',
    };
    final unexpected = hosts
        .where((h) => !allowed.contains(h) && !h.endsWith('.') && !h.endsWith('.example') && !h.contains('example.'))
        .toSet();
    expect(unexpected, isEmpty, reason: 'new network host in lib/: $unexpected');
  });
}
