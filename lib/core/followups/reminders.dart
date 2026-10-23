import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
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

  /// When each open follow-up should remind: at its time if that is still ahead;
  /// one due earlier today that has not been caught up yet ([caughtUp] holds
  /// "personId|date") a minute from now, so setting a follow-up for today still
  /// gives a reminder (phone test F31). Older ones stay in the Follow-ups list only.
  @visibleForTesting
  static List<(FollowupItem, DateTime)> plan(List<FollowupItem> open, DateTime now, Set<String> caughtUp) => [
    for (final f in open)
      if (f.due.isAfter(now))
        (f, f.due)
      else if (_sameDay(f.due, now) && !caughtUp.contains(_key(f, now)))
        (f, now.add(const Duration(minutes: 1))),
  ];

  static bool _sameDay(DateTime a, DateTime b) {
    final x = a.toLocal(), y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  static String _key(FollowupItem f, DateTime day) {
    final d = day.toLocal();
    return '${f.personId}|${d.year}-${d.month}-${d.day}';
  }

  /// Same-day catch-ups already given, so reopening the app does not repeat them.
  static Future<File> _caughtUpFile() async =>
      File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}reminders_caught_up.txt');

  /// Replaces every scheduled reminder with [open].
  static Future<void> sync(List<FollowupItem> open, {DateTime? now}) async {
    if (!_android) return;
    await init();
    final t = now ?? DateTime.now();
    // Asked as soon as any follow-up is set, today's included (phone test F31).
    if (open.isNotEmpty && !_asked) {
      _asked = true;
      await requestPermission();
    }
    final file = await _caughtUpFile();
    final today = '|${t.year}-${t.month}-${t.day}';
    final caughtUp = {
      for (final l in file.existsSync() ? await file.readAsLines() : const <String>[])
        if (l.endsWith(today)) l,
    };
    final planned = plan(open, t, caughtUp);
    final added = [
      for (final (f, _) in planned)
        if (!f.due.isAfter(t)) _key(f, t),
    ];
    if (added.isNotEmpty) await file.writeAsString([...caughtUp, ...added].join('\n'));
    // Cancel only scheduled reminders no longer wanted; cancelAll also cleared
    // today's reminder already showing (audit MOB-REL-0007).
    // A catch-up scheduled on an earlier open this minute is still wanted.
    final wanted = {
      for (final (f, _) in planned) idFor(f.personId),
      for (final f in open)
        if (caughtUp.contains(_key(f, t))) idFor(f.personId),
    };
    for (final p in await _plugin.pendingNotificationRequests()) {
      if (!wanted.contains(p.id)) await _plugin.cancel(id: p.id);
    }
    for (final (f, at) in planned) {
      await _plugin.zonedSchedule(
        id: idFor(f.personId),
        title: 'Follow up with ${f.name.isEmpty ? 'a contact' : f.name}',
        body: [if (f.company != null) f.company!, if (f.eventName != null) 'met at ${f.eventName}'].join(' · '),
        scheduledDate: tz.TZDateTime.from(at, tz.UTC), // an exact instant; the UTC label only carries it
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
