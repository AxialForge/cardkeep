import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/contacts/contact_detail_screen.dart';
import '../features/contacts/contact_edit_screen.dart';
import '../features/contacts/contacts_screen.dart';
import '../features/debug/ocr_capture_screen.dart';
import '../features/placeholder/coming_soon_screen.dart';
import '../features/scan/queue_screen.dart';
import '../features/scan/scan_review.dart';
import '../features/scan/scan_screen.dart';
import '../features/settings/settings_screen.dart';
import '../scan/scan_pipeline.dart';
import 'drawer.dart';

/// The app's root navigator; used to show the startup update notice.
final rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter buildRouter({String initialLocation = '/'}) => GoRouter(
  navigatorKey: rootNavigatorKey,
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
    GoRoute(path: '/scan', builder: (_, _) => const ScanScreen()),
    GoRoute(path: '/queue', builder: (_, _) => const QueueScreen()),
    GoRoute(
      path: '/scan/crop',
      builder: (_, s) => ManualCropScreen(side: s.extra! as ScannedSide),
    ),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    GoRoute(path: '/debug/ocr', builder: (_, _) => const OcrCaptureScreen()),
    for (final d in allDestinations.where((d) => d.milestone != null))
      GoRoute(
        path: d.path,
        builder: (_, _) => ComingSoonScreen(destination: d),
      ),
  ],
);
