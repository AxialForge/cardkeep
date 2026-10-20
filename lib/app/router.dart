import 'package:go_router/go_router.dart';

import '../features/contacts/contact_detail_screen.dart';
import '../features/contacts/contact_edit_screen.dart';
import '../features/contacts/contacts_screen.dart';
import '../features/debug/ocr_capture_screen.dart';
import '../features/placeholder/coming_soon_screen.dart';
import '../features/settings/settings_screen.dart';
import 'drawer.dart';

GoRouter buildRouter({String initialLocation = '/'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/', builder: (_, _) => const ContactsScreen()),
    GoRoute(path: '/contact/new', builder: (_, _) => const ContactEditScreen()),
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
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    GoRoute(path: '/debug/ocr', builder: (_, _) => const OcrCaptureScreen()),
    for (final d in allDestinations.where((d) => d.milestone != null))
      GoRoute(
        path: d.path,
        builder: (_, _) => ComingSoonScreen(destination: d),
      ),
  ],
);
