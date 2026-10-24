import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import 'content/content_model.dart';
import 'content/help_content.dart';
import 'content/welcome_content.dart';
import 'onboarding_gate.dart';
import 'onboarding_pages.dart';
import 'onboarding_providers.dart';

enum TourSection {
  welcome('Welcome'),
  permissions('Permissions'),
  setup('Set-up'),
  lessons('Lessons'),
  start('Get started');

  final String label;
  const TourSection(this.label);
}

class _TourPage {
  final String id;
  final TourSection section;
  final Widget Function(int index) build;
  const _TourPage(this.id, this.section, this.build);
}

/// The guided tour (S15a): welcome, permissions, set-up, lessons, get started.
/// Skippable at every step; the back button steps back.
class OnboardingScreen extends ConsumerStatefulWidget {
  /// Replaying from Settings: nothing is marked done, and leaving just goes back.
  final bool replay;
  final int startPage;
  const OnboardingScreen({super.key, this.replay = false, this.startPage = 0});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final PageController _controller = PageController(initialPage: widget.startPage);
  late int _page = widget.startPage;
  late bool _backupOn = !widget.replay;
  bool _backupApplied = false;
  bool _busy = false;

  late final List<_TourPage> _pages = [
    for (final w in welcomePages) _TourPage('welcome-${w.id}', TourSection.welcome, (_) => WelcomeView(w)),
    for (final p in permissionCards) _TourPage('perm-${p.id}', TourSection.permissions, (_) => PermissionView(p)),
    _TourPage('setup-look', TourSection.setup, (_) => const SetupLookView()),
    _TourPage('setup-features', TourSection.setup, (_) => const SetupFeaturesView()),
    _TourPage(
      'setup-backup',
      TourSection.setup,
      (_) => SetupBackupView(
        value: _backupOn,
        onChanged: (v) => setState(() {
          _backupOn = v;
          _backupApplied = false;
        }),
      ),
    ),
    for (var i = 0; i < lessons.length; i++)
      _TourPage(
        'lesson-${lessons[i].id}',
        TourSection.lessons,
        (_) => LessonView(lessons[i], number: i + 1, total: lessons.length),
      ),
    _TourPage('finale', TourSection.start, (_) => _FinaleView(replay: widget.replay, onChoose: _finish)),
  ];

  int get _backupIndex => _pages.indexWhere((p) => p.id == 'setup-backup');
  int get _finaleIndex => _pages.length - 1;
  bool get _onFinale => _page == _finaleIndex;

  @override
  void initState() {
    super.initState();
    if (widget.replay) {
      ref.read(settingsRepoProvider).autoBackup().then((v) {
        if (mounted) setState(() => _backupOn = v);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The weekly backup choice is saved when you leave its page, so a quick
  /// Skip never turns it on by itself.
  Future<void> _applyBackup() async {
    if (_backupApplied) return;
    _backupApplied = true;
    await ref.read(settingsRepoProvider).setAutoBackup(_backupOn);
  }

  Future<void> _goTo(int i) async {
    if (i < 0 || i >= _pages.length) return;
    if (_page == _backupIndex && i != _backupIndex) await _applyBackup();
    final reduce = mounted && MediaQuery.of(context).disableAnimations;
    if (reduce) {
      _controller.jumpToPage(i);
    } else {
      await _controller.animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    }
  }

  void _next() => _goTo(_page + 1);
  void _prev() => _goTo(_page - 1);

  Future<void> _skip() async {
    final ok = await confirm(
      context,
      title: 'Skip the tour?',
      message: widget.replay
          ? 'You can replay it any time from Settings, under Help.'
          : 'You can replay it any time from Settings, under Help. First-visit tips will stay off.',
      action: 'Skip',
    );
    if (!ok || !mounted) return;
    if (!widget.replay) {
      final s = ref.read(settingsRepoProvider);
      await s.setOnboardingVersion(tourVersion);
      await s.setWhatsNewSeen(tourVersion);
      await s.setTipsEnabled(false);
    }
    _leave();
  }

  void _leave({String? then}) {
    if (!mounted) return;
    final router = GoRouter.of(context);
    if (widget.replay && router.canPop()) {
      router.pop();
    } else {
      router.go('/');
    }
    // Once Contacts is showing, open the chosen screen on top of it.
    if (then != null) WidgetsBinding.instance.addPostFrameCallback((_) => router.push(then));
  }

  Future<void> _finish(_Finish how) async {
    if (_busy) return;
    setState(() => _busy = true);
    await _applyBackup();
    final s = ref.read(settingsRepoProvider);
    if (!widget.replay) {
      await s.setOnboardingVersion(tourVersion);
      await s.setWhatsNewSeen(tourVersion);
      await s.setTipsEnabled(true);
    }
    if (how == _Finish.demo) {
      await ref.read(demoDataProvider).add(region: ref.read(regionProvider).value ?? 'US');
    }
    if (!mounted) return;
    _leave(
      then: switch (how) {
        _Finish.scan => '/scan',
        _Finish.import => '/import',
        _ => null,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final section = _pages[_page].section;
    final inWelcome = section == TourSection.welcome;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_page > 0) {
          _prev();
        } else {
          _skip();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Tokens.gutter, 8, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        label: 'Step ${_page + 1} of ${_pages.length}, ${section.label}',
                        child: ExcludeSemantics(
                          child: Text('${section.label}  ·  ${_page + 1} of ${_pages.length}', style: AppText.label),
                        ),
                      ),
                    ),
                    TextButton(onPressed: _skip, child: Text(widget.replay ? 'Close' : 'Skip tour')),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Tokens.gutter),
                child: ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: (_page + 1) / _pages.length,
                      minHeight: 5,
                      color: Tokens.brass,
                      backgroundColor: Tokens.hairline,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) {
                    final left = _page;
                    setState(() => _page = i);
                    if (left == _backupIndex && i != _backupIndex) _applyBackup();
                  },
                  itemBuilder: (context, i) => _pages[i].build(i),
                ),
              ),
              if (inWelcome)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Semantics(
                    label: 'Page ${_page + 1} of ${welcomePages.length}',
                    child: ExcludeSemantics(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < welcomePages.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: i == _page ? 22 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: i == _page ? Tokens.brass : Tokens.hairline,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (!_onFinale) _bottomBar(),
              if (_onFinale)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Tokens.gutter, 0, Tokens.gutter, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _prev,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final section = _pages[_page].section;
    final id = _pages[_page].id;
    final label = switch (section) {
      TourSection.welcome => _page == welcomePages.length - 1 ? 'Let\'s start' : 'Next',
      TourSection.permissions => 'Continue',
      TourSection.setup => id == 'setup-backup' ? 'Continue' : 'Next',
      TourSection.lessons => _page == _pages.length - 2 ? 'Finish lessons' : 'Next lesson',
      TourSection.start => 'Next',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.gutter, 4, Tokens.gutter, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (_page > 0) OutlinedButton(onPressed: _prev, child: const Text('Back')) else const SizedBox.shrink(),
              if (_page > 0) const SizedBox(width: 10),
              Expanded(
                child: FilledButton(onPressed: _next, child: Text(label)),
              ),
            ],
          ),
          if (section == TourSection.lessons)
            TextButton(onPressed: () => _goTo(_finaleIndex), child: const Text('Skip the rest of the lessons')),
        ],
      ),
    );
  }
}

enum _Finish { scan, import, demo, empty }

class _FinaleView extends ConsumerWidget {
  final bool replay;
  final Future<void> Function(_Finish) onChoose;
  const _FinaleView({required this.replay, required this.onChoose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demo = ref.watch(demoCountProvider).value ?? 0;
    return TourPage(
      art: Art.demo,
      title: replay ? 'That\'s the tour' : 'You\'re ready',
      lead: 'Pick how to begin. Nothing here is permanent.',
      children: [
        FilledButton.icon(
          onPressed: () => onChoose(_Finish.scan),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Scan your first card'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => onChoose(_Finish.import),
          icon: const Icon(Icons.login),
          label: const Text('Import contacts'),
        ),
        const SizedBox(height: 6),
        Panel(
          margin: EdgeInsets.zero,
          padding: EdgeInsets.zero,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text('How to bring contacts from…', style: AppText.body),
              children: [
                for (final h in importHowTos)
                  ExpansionTile(
                    title: Text(h.source, style: AppText.bodyStrong),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < h.steps.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('${i + 1}. ${h.steps[i]}', style: AppText.body),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: demo > 0 ? null : () => onChoose(_Finish.demo),
          icon: const Icon(Icons.groups_outlined),
          label: Text(demo > 0 ? 'Demo contacts already added' : 'Start with demo data'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: Text(
            'Adds six made-up contacts (five people and a shop), all tagged Demo. Remove them in one tap from Settings, Help.',
            style: AppText.secondary,
          ),
        ),
        const SizedBox(height: 10),
        TextButton(onPressed: () => onChoose(_Finish.empty), child: Text(replay ? 'Done' : 'Start empty')),
      ],
    );
  }
}
