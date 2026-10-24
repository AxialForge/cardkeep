import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'providers.dart';
import 'theme.dart';

/// One drawer destination. [milestone] set = not built yet (shows a placeholder).
class Destination {
  final String path;
  final String label;
  final IconData icon;
  final String? milestone;
  const Destination(this.path, this.label, this.icon, {this.milestone});
}

const mainDestinations = [
  Destination('/', 'Contacts', Icons.person_outline),
  Destination('/events', 'Events', Icons.calendar_today_outlined),
  Destination('/career', 'Career moves', Icons.swap_horiz),
  Destination('/scan', 'Scan cards', Icons.photo_camera_outlined),
  Destination('/tap', 'Tap cards (NFC)', Icons.contactless_outlined),
  Destination('/queue', 'Review queue', Icons.notes),
  Destination('/followups', 'Follow-ups', Icons.schedule),
  Destination('/duplicates', 'Duplicates', Icons.filter_none),
  Destination('/tags', 'Tags', Icons.sell_outlined),
  Destination('/import', 'Import', Icons.login),
  Destination('/export', 'Export and backup', Icons.download_outlined),
  Destination('/help', 'Help & tips', Icons.help_outline),
  // Sync to desktop (0.8) is listed again once it is built (audit MOB-UX-0002).
];

const footerDestinations = [
  Destination('/mycard', 'My card', Icons.badge_outlined),
  Destination('/settings', 'Settings', Icons.settings_outlined),
];

final allDestinations = [...mainDestinations, ...footerDestinations];

class AppDrawer extends ConsumerWidget {
  final String current;
  const AppDrawer({super.key, required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider).value;
    final n = NumberFormat.decimalPattern();

    Widget item(Destination d, {int? count}) {
      final selected = d.path == current;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        child: ListTile(
          dense: true,
          selected: selected,
          selectedTileColor: Tokens.selected,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          leading: Icon(d.icon, size: 22, color: Tokens.ink),
          title: Text(d.label, style: selected ? AppText.bodyStrong : AppText.body),
          trailing: count != null && count > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Tokens.amberBg, borderRadius: BorderRadius.circular(99)),
                  child: Text('$count', style: AppText.label.copyWith(color: Tokens.amberFg)),
                )
              : null,
          onTap: () {
            Navigator.pop(context);
            // Top-level sections replace each other: Back from any of them goes to
            // Contacts, then leaves the app (audit MOB-UX-0001).
            if (selected) return;
            context.go('/');
            if (d.path != '/') context.push(d.path);
          },
        ),
      );
    }

    final header = Container(
      width: double.infinity,
      color: Tokens.strong,
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 16, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Tokens.brandIvory, borderRadius: BorderRadius.circular(10)),
                child: Image.asset('assets/brand/cardkeep-mark-256.png', semanticLabel: 'CardKeep logo'),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CardKeep', style: AppText.heading.copyWith(color: Tokens.onStrong)),
                    Text(
                      'Your professional network',
                      style: AppText.secondary.copyWith(color: Tokens.onStrongMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat(n.format(stats?.people ?? 0), 'People'),
              const SizedBox(width: 24),
              _Stat(n.format(stats?.companies ?? 0), 'Companies'),
            ],
          ),
        ],
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Drawer(
        shape: const RoundedRectangleBorder(),
        // One scroll view for everything, so every entry can be reached on any
        // screen and font size; a fade at the bottom shows there is more (phone test F4).
        child: _FadeWhenMore(
          child: ListView(
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 8),
            children: [
              header,
              const SizedBox(height: 6),
              for (final d in mainDestinations)
                item(
                  d,
                  count: switch (d.path) {
                    '/followups' => stats?.followupsThisWeek,
                    '/queue' => ref.watch(queueProvider).value?.length,
                    _ => null,
                  },
                ),
              const Divider(),
              for (final d in footerDestinations) item(d),
              if (kDebugMode) item(const Destination('/debug/ocr', 'OCR capture (debug)', Icons.bug_report_outlined)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fades the bottom edge of a scrolling child while there is more below it.
class _FadeWhenMore extends StatefulWidget {
  final Widget child;
  const _FadeWhenMore({required this.child});
  @override
  State<_FadeWhenMore> createState() => _FadeWhenMoreState();
}

class _FadeWhenMoreState extends State<_FadeWhenMore> {
  bool _more = false;

  bool _onMetrics(ScrollMetrics m) {
    final more = m.extentAfter > 4;
    if (more != _more) setState(() => _more = more);
    return false;
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollMetricsNotification>(
    onNotification: (n) => _onMetrics(n.metrics),
    child: NotificationListener<ScrollNotification>(
      onNotification: (n) => _onMetrics(n.metrics),
      child: Stack(
        children: [
          widget.child,
          if (_more)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  height: 56,
                  alignment: Alignment.bottomCenter,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Tokens.surface.withValues(alpha: 0), Tokens.surface],
                    ),
                  ),
                  child: Icon(Icons.keyboard_arrow_down, color: Tokens.ink2),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: AppText.title.copyWith(color: Tokens.onStrong, fontSize: 24)),
      Text(label, style: AppText.secondary.copyWith(color: Tokens.onStrongMuted, fontSize: 12)),
    ],
  );
}
