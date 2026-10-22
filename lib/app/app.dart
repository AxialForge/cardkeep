import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/followups/followups_repository.dart';
import '../core/followups/reminders.dart';
import '../core/update/updater.dart';
import '../features/events/events_screens.dart';
import '../features/followups/followups_screen.dart';
import '../features/settings/update_sheet.dart';
import '../features/transfer/transfer_screens.dart';
import '../scan/scan_worker.dart';
import 'providers.dart';
import 'router.dart';
import 'theme.dart';

class CardOrganizerApp extends ConsumerStatefulWidget {
  final String initialLocation;
  const CardOrganizerApp({super.key, this.initialLocation = '/'});

  @override
  ConsumerState<CardOrganizerApp> createState() => _CardOrganizerAppState();
}

class _CardOrganizerAppState extends ConsumerState<CardOrganizerApp> {
  late final GoRouter _router = buildRouter(initialLocation: widget.initialLocation);
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startupUpdateCheck();
      _recoverScans();
      _autoStartEvent();
      _startReminders();
      _autoBackup();
      _incomingVcf();
    });
  }

  /// Captures that were never read (app closed mid-scan) are read now and
  /// land in the review queue (spec: never lose a capture).
  Future<void> _recoverScans() async {
    try {
      final n = await ref.read(scanWorkerProvider.notifier).recover();
      if (n > 0) {
        _messenger.currentState?.showSnackBar(
          SnackBar(content: Text('Reading $n card${n == 1 ? '' : 's'} left from last time')),
        );
      }
    } catch (_) {
      // No image store yet (first launch, tests): nothing to recover.
    }
  }

  /// An auto-scan event running today opens its scan session (S10.4); no
  /// background job, just the first open of the day.
  Future<void> _autoStartEvent() async {
    try {
      final e = await ref.read(eventsRepoProvider).autoStartIfDue();
      if (e != null) {
        _messenger.currentState?.showSnackBar(
          SnackBar(content: Text('Scanning for ${e.name}: new cards go to this event')),
        );
      }
    } catch (_) {}
  }

  /// Only when switched on in Settings (off by default), Android only, once per launch.
  Future<void> _startupUpdateCheck() async {
    if (defaultTargetPlatform != TargetPlatform.android || kDebugMode) return;
    if (!await ref.read(settingsRepoProvider).updateOnStart()) return;
    try {
      final info = await Updater.check();
      if (!info.available) return;
      _messenger.currentState?.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          content: Text('CardKeep ${info.latest} is available'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              final ctx = rootNavigatorKey.currentContext;
              if (ctx != null) showUpdateSheet(ctx);
            },
          ),
        ),
      );
    } on UpdateException {
      // Offline or rate-limited: say nothing at startup.
    }
  }

  /// A .vcf opened or shared from another app opens Import (S13.4).
  static const _incoming = MethodChannel('cardkeep/incoming');
  Future<void> _incomingVcf() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _incoming.setMethodCallHandler((call) async {
      if (call.method == 'vcf' && call.arguments is Uint8List) await _router.push('/import', extra: call.arguments);
    });
    try {
      final bytes = await _incoming.invokeMethod<Uint8List>('takeVcf');
      if (bytes != null) await _router.push('/import', extra: bytes);
    } catch (_) {}
  }

  /// Weekly backup when due and switched on (S13.10).
  Future<void> _autoBackup() async {
    try {
      if (!await ref.read(settingsRepoProvider).autoBackup()) return;
      final b = await ref.read(backupsProvider.future);
      await b.autoBackupIfDue(appVersion: (await PackageInfo.fromPlatform()).version);
    } catch (_) {}
  }

  /// Follow-up reminders (S11): a tap opens the contact, also when the tap
  /// started the app.
  Future<void> _startReminders() async {
    try {
      Reminders.onOpen = (id) => _router.push('/contact/$id');
      final launched = await Reminders.launchPerson();
      if (launched != null) await _router.push('/contact/$launched');
    } catch (_) {}
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  /// Tokens are read at build time, so a palette change rebuilds every element
  /// (the same walk hot reload does). Navigation state is kept.
  void _rebuildAll() {
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    (context as Element).visitChildren(mark);
  }

  @override
  Widget build(BuildContext context) {
    // Every change to the open follow-ups re-schedules the reminders (S11.6:
    // also on each app start, so nothing is lost after an update or reboot).
    ref.listen<AsyncValue<List<FollowupItem>>>(openFollowupsProvider, (_, next) {
      if (next.value case final open?) Reminders.sync(open).catchError((Object _) {});
    });
    // Rebuilds when the phone switches between light and dark mode.
    final platform = MediaQuery.platformBrightnessOf(context);
    final choice = ref.watch(themeChoiceProvider).value ?? AppPalette.systemId;
    final palette = AppPalette.resolve(choice, platform);
    if (!identical(palette, AppPalette.current)) {
      AppPalette.current = palette;
      WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildAll());
    }
    return MaterialApp.router(
      title: 'CardKeep',
      scaffoldMessengerKey: _messenger,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: _router,
    );
  }
}
