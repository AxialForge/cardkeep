import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'followups_repository.dart';

/// Follow-up notifications (S11.4-S11.9). Local only: nothing leaves the phone.
/// One notification per open follow-up, at its date (08:00). Inexact delivery
/// (allowed while idle), so no exact-alarm permission is needed; a reminder
/// can arrive a few minutes late. The plugin's boot receiver re-schedules after
/// a reboot, and [sync] re-schedules everything on every app start.
class Reminders {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static bool _asked = false;

  /// Called with the person id when a reminder is tapped.
  static void Function(String personId)? onOpen;

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> init() async {
    if (_ready || !_android) return;
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) {
        final id = r.payload;
        if (id != null && id.isNotEmpty) onOpen?.call(id);
      },
    );
    _ready = true;
  }

  /// The person whose reminder launched the app, if any (S11.9).
  static Future<String?> launchPerson() async {
    if (!_android) return null;
    await init();
    final d = await _plugin.getNotificationAppLaunchDetails();
    if (d?.didNotificationLaunchApp ?? false) return d!.notificationResponse?.payload;
    return null;
  }

  /// Android 13+ asks once (S11.7); returns whether reminders can show.
  static Future<bool> requestPermission() async {
    if (!_android) return false;
    await init();
    final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await a?.requestNotificationsPermission() ?? false;
  }

  /// Stable across launches and Dart versions (String.hashCode is not): FNV-1a
  /// over the uuid (audit MOB-REL-0007).
  static int idFor(String personId) {
    var h = 0x811c9dc5;
    for (final c in personId.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h & 0x3fffffff;
  }

  /// Replaces every scheduled reminder with [open] (future dates only).
  static Future<void> sync(List<FollowupItem> open, {DateTime? now}) async {
    if (!_android) return;
    await init();
    final t = now ?? DateTime.now();
    final future = open.where((f) => f.due.isAfter(t)).toList();
    if (future.isNotEmpty && !_asked) {
      _asked = true;
      await requestPermission();
    }
    // Cancel only scheduled reminders no longer wanted; cancelAll also cleared
    // today's reminder already showing (audit MOB-REL-0007).
    final wanted = {for (final f in future) idFor(f.personId)};
    for (final p in await _plugin.pendingNotificationRequests()) {
      if (!wanted.contains(p.id)) await _plugin.cancel(id: p.id);
    }
    for (final f in future) {
      await _plugin.zonedSchedule(
        id: idFor(f.personId),
        title: 'Follow up with ${f.name.isEmpty ? 'a contact' : f.name}',
        body: [if (f.company != null) f.company!, if (f.eventName != null) 'met at ${f.eventName}'].join(' · '),
        scheduledDate: tz.TZDateTime.from(f.due, tz.UTC), // an exact instant; the UTC label only carries it
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'followups',
            'Follow-up reminders',
            channelDescription: 'On the day you planned to follow up with someone',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            // On the lock screen only "CardKeep" shows, not who or where (MOB-SEC-0002).
            visibility: NotificationVisibility.private,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: f.personId,
      );
    }
  }
}
