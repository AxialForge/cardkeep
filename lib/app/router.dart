import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../core/contacts/contact_models.dart';
import '../core/platform/platform_info.dart';
import '../features/about/about_screen.dart';
import '../features/about/changelog_screen.dart';
import '../features/career/career_screens.dart';
import '../features/contacts/company_screen.dart';
import '../features/contacts/contact_detail_screen.dart';
import '../features/contacts/contact_edit_screen.dart';
import '../features/debug/ocr_capture_screen.dart';
import '../features/desktop/desktop_home.dart';
import '../features/duplicates/duplicates_screen.dart';
import '../features/duplicates/merge_screen.dart';
import '../features/events/events_screens.dart';
import '../features/followups/followups_screen.dart';
import '../features/mycard/my_card_screen.dart';
import '../features/onboarding/help_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/placeholder/coming_soon_screen.dart';
import '../features/scan/queue_screen.dart';
import '../features/scan/scan_review.dart';
import '../features/scan/scan_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/sync/conflicts_screen.dart';
import '../features/sync/desktop_sync_screen.dart';
import '../features/sync/sync_screen.dart';
import '../features/tags/tags_screen.dart';
import '../features/tap/tap_screen.dart';
import '../features/transfer/transfer_screens.dart';
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
    GoRoute(path: '/', builder: (_, _) => const DesktopHome()),
    GoRoute(
      path: '/contact/new',
      builder: (_, s) => ContactEditScreen(
        scan: s.extra is ScanHandoff ? s.extra! as ScanHandoff : null,
        prefill: s.extra is ContactDraft ? s.extra! as ContactDraft : null,
      ),
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
      path: '/company/:id',
      builder: (_, s) => CompanyScreen(id: s.pathParameters['id']!),
    ),
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
    GoRoute(path: '/career', builder: (_, _) => const CareerScreen()),
    GoRoute(path: '/export', builder: (_, _) => const ExportScreen()),
    GoRoute(path: '/sync', builder: (_, _) => PlatformInfo.isDesktop ? const DesktopSyncScreen() : const SyncScreen()),
    GoRoute(path: '/sync/conflicts', builder: (_, _) => const ConflictsScreen()),
    GoRoute(
      path: '/import',
      builder: (_, s) => switch (s.extra) {
        final Uint8List v => ImportScreen(vcf: v),
        final List<List<String>> c => ImportScreen(csv: c),
        _ => const ImportScreen(),
      },
    ),
    GoRoute(
      path: '/import/csv',
      builder: (_, s) => CsvMappingScreen(rows: s.extra! as List<List<String>>),
    ),
    GoRoute(path: '/mycard', builder: (_, _) => const MyCardScreen()),
    GoRoute(path: '/tap', builder: (_, _) => const TapScreen()),
    GoRoute(path: '/tags', builder: (_, _) => const TagsScreen()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    GoRoute(
      path: '/welcome',
      builder: (_, s) => OnboardingScreen(
        replay: s.uri.queryParameters['replay'] == '1',
        startPage: int.tryParse(s.uri.queryParameters['page'] ?? '') ?? 0,
      ),
    ),
    GoRoute(path: '/help', builder: (_, _) => const HelpScreen()),
    GoRoute(path: '/about', builder: (_, _) => const AboutScreen()),
    GoRoute(path: '/about/changelog', builder: (_, _) => const ChangelogScreen()),
    GoRoute(
      path: '/help/:id',
      builder: (_, s) => HelpArticleScreen(id: s.pathParameters['id']!),
    ),
    GoRoute(path: '/debug/ocr', builder: (_, _) => const OcrCaptureScreen()),
    for (final d in allDestinations.where((d) => d.milestone != null))
      GoRoute(
        path: d.path,
        builder: (_, _) => ComingSoonScreen(destination: d),
      ),
  ],
);
