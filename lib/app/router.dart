import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/contacts/contact_detail_screen.dart';
import '../features/contacts/contact_edit_screen.dart';
import '../features/contacts/contacts_screen.dart';
import '../features/debug/ocr_capture_screen.dart';
import '../features/duplicates/duplicates_screen.dart';
import '../features/duplicates/merge_screen.dart';
import '../features/events/events_screens.dart';
import '../features/followups/followups_screen.dart';
import '../features/placeholder/coming_soon_screen.dart';
import '../features/scan/queue_screen.dart';
import '../features/scan/scan_review.dart';
import '../features/scan/scan_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/tags/tags_screen.dart';
import '../scan/scan_pipeline.dart';
import 'drawer.dart';

/// The app's root navigator; used to show the startup update notice.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Lets a screen know when another screen covers it or it comes back on top
/// (the scanner frees the camera while covered).
final routeObserver = RouteObserver<ModalRoute<void>>();

GoRouter buildRouter({String initialLocation = '/'}) => GoRouter(
  navigatorKey: rootNavigatorKey,
  observers: [routeObserver],
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/', builder: (_, _) => const ContactsScreen()),
    GoRoute(
      path: '/contact/new',
      builder: (_, s) => ContactEditScreen(scan: s.extra as ScanHandoff?),
    ),
    GoRoute(
      path: '/contact/:id',
      builder: (_, s) => ContactDetailScreen(id: s.pathParameters['id']!),
      routes: [
        GoRoute(
          path: 'edit',
          builder: (_, s) => ContactEditScreen(id: s.pathParameters['id']),
        ),
      ],
    ),
    GoRoute(
      path: '/scan',
      builder: (_, s) => ScanScreen(mode: s.uri.queryParameters['mode'], pick: s.uri.queryParameters['pick'] == '1'),
    ),
    GoRoute(path: '/queue', builder: (_, _) => const QueueScreen()),
    GoRoute(
      path: '/scan/crop',
      builder: (_, s) => ManualCropScreen(side: s.extra! as ScannedSide),
    ),
    GoRoute(path: '/duplicates', builder: (_, _) => const DuplicatesScreen()),
    GoRoute(
      path: '/merge/:a/:b',
      builder: (_, s) => MergeScreen(a: s.pathParameters['a']!, b: s.pathParameters['b']!),
    ),
    GoRoute(path: '/events', builder: (_, _) => const EventsScreen()),
    GoRoute(path: '/event/new', builder: (_, _) => const EventEditScreen()),
    GoRoute(
      path: '/event/:id',
      builder: (_, s) => EventDetailScreen(id: s.pathParameters['id']!),
      routes: [
        GoRoute(
          path: 'edit',
          builder: (_, s) => EventEditScreen(id: s.pathParameters['id']),
        ),
      ],
    ),
    GoRoute(path: '/followups', builder: (_, _) => const FollowupsScreen()),
    GoRoute(path: '/tags', builder: (_, _) => const TagsScreen()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    GoRoute(path: '/debug/ocr', builder: (_, _) => const OcrCaptureScreen()),
    for (final d in allDestinations.where((d) => d.milestone != null))
      GoRoute(
        path: d.path,
        builder: (_, _) => ComingSoonScreen(destination: d),
      ),
  ],
);
