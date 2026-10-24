import 'package:axial_app_kit/axial_app_kit.dart' show ThemeChoice;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/contacts/purge.dart';
import '../core/followups/followups_repository.dart';
import '../core/followups/reminders.dart';
import '../core/transfer/backup.dart';
import '../core/update/updater.dart';
import '../features/events/events_screens.dart';
import '../features/followups/followups_screen.dart';
import '../features/onboarding/onboarding_gate.dart';
import '../features/onboarding/whats_new_sheet.dart';
import '../features/settings/update_sheet.dart';
import '../features/shared/sensitive_clipboard.dart';
import '../features/transfer/transfer_screens.dart';
import '../scan/scan_worker.dart';
import 'providers.dart';
import 'router.dart';
import 'theme.dart';
import 'theme_family.dart';

class CardOrganizerApp extends ConsumerStatefulWidget {
  final String initialLocation;

  /// Off in tests that open the app on an empty library without the tour (S15a.8).
  final bool showOnboarding;
  const CardOrganizerApp({super.key, this.initialLocation = '/', this.showOnboarding = true});

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
      _restoreMessage();
      _purge();
      _hideInRecents();
      _onboarding();
    });
  }

  /// First launch runs the tour; an existing user upgrading gets a short
  /// What's new sheet instead (S15a.8).
  Future<void> _onboarding() async {
    if (!widget.showOnboarding) return;
    try {
      final settings = ref.read(settingsRepoProvider);
      final done = await settings.onboardingVersion();
      if (done != null) return;
      final counts = await ref
          .read(databaseProvider)
          .customSelect('SELECT (SELECT COUNT(*) FROM people) + (SELECT COUNT(*) FROM cards) AS n')
          .getSingle();
      switch (decideOnboarding(
        doneVersion: done,
        whatsNewSeen: await settings.whatsNewSeen(),
        hasData: counts.read<int>('n') > 0,
      )) {
        case OnboardingStart.tour:
          _router.go('/welcome');
        case OnboardingStart.whatsNew:
          final ctx = rootNavigatorKey.currentContext;
          if (ctx == null || !ctx.mounted) return;
          final choice = await showWhatsNewSheet(ctx, ref);
          if (choice == WhatsNewChoice.tour) await _router.push('/welcome?replay=1');
        case OnboardingStart.none:
          break;
      }
    } catch (_) {
      // Never block the app on the tour.
    }
  }

  /// Captures that were never read (app closed mid-scan) are read now and
  /// land in the review queue (spec: never lose a capture).
  Future<void> _recoverScans() async {
    ScanWorker.onSetAside = () => _messenger.currentState?.showSnackBar(
      const SnackBar(content: Text('A capture could not be read after 3 tries and was set aside')),
    );
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
          persist: false,
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

  /// Contacts deleted more than [retention] ago are removed for good, with
  /// their card photos and logos (audit MOB-PRV-0002).
  Future<void> _purge() async {
    try {
      await purgeDeleted(
        ref.read(databaseProvider),
        before: DateTime.now().subtract(retention),
        store: await ref.read(imageStoreProvider.future),
      );
    } catch (e) {
      debugPrint('Purge failed: $e');
    }
  }

  /// The saved Hide in recents choice applies from the first frame (MOB-SEC-0004).
  Future<void> _hideInRecents() async {
    try {
      if (await ref.read(settingsRepoProvider).watchHideInRecents().first) await setHideInRecents(true);
    } catch (_) {}
  }

  /// After a restore at start: say how it went (audit MOB-REL-0003).
  void _restoreMessage() {
    final text = switch (lastRestoreOutcome) {
      RestoreOutcome.restored => 'Backup restored. Your previous data is kept as a fallback copy.',
      RestoreOutcome.refused => 'That backup could not be restored (it looks damaged). Your data is unchanged.',
      RestoreOutcome.failed =>
        'The restore did not finish. It continues the next time you open CardKeep; nothing is lost.',
      RestoreOutcome.none => null,
    };
    if (text != null) {
      _messenger.currentState?.showSnackBar(SnackBar(duration: const Duration(seconds: 8), content: Text(text)));
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
    // Loads the place category labels (S14b.6) and keeps them current app-wide.
    ref.watch(placeCategoriesProvider);
    // Every change to the open follow-ups re-schedules the reminders (S11.6:
    // also on each app start, so nothing is lost after an update or reboot).
    ref.listen<AsyncValue<bool>>(hideInRecentsProvider, (_, next) {
      if (next.value case final on?) setHideInRecents(on);
    });
    ref.listen<AsyncValue<List<FollowupItem>>>(openFollowupsProvider, (_, next) {
      if (next.value case final open?) Reminders.sync(open).catchError((Object _) {});
    });
    // Rebuilds when the phone switches between light and dark mode.
    final platform = MediaQuery.platformBrightnessOf(context);
    final choice = ref.watch(themeChoiceProvider).value ?? AppPalette.systemId;
    final palette = ThemeChoice.parse(choice, catalog: cardkeepThemes).palette(platform);
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
