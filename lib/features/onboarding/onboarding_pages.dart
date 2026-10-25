import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/settings/regions.dart';
import '../settings/app_lock_tiles.dart';
import '../settings/theme_picker.dart';
import 'content/content_model.dart';
import 'lesson_art.dart';
import 'onboarding_providers.dart';
import 'permission_service.dart';

/// Shared page frame: scrolls, keeps its gutters, announces its title.
class TourPage extends StatelessWidget {
  final Art? art;
  final String title;
  final String? lead;
  final List<Widget> children;
  const TourPage({super.key, this.art, required this.title, this.lead, this.children = const []});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(Tokens.gutter, 8, Tokens.gutter, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (art != null) ...[LessonArt(art!), const SizedBox(height: 16)],
        Semantics(header: true, child: Text(title, style: AppText.title)),
        if (lead != null) ...[const SizedBox(height: 6), Text(lead!, style: AppText.body)],
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );
}

/// A numbered step in a lesson or article.
class StepTile extends StatelessWidget {
  final int number;
  final LessonStep step;
  const StepTile(this.number, this.step, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Semantics(
      container: true,
      label: 'LessonStep $number: ${step.title}. ${step.body}',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Tokens.brass.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: Text(
                '$number',
                textScaler: TextScaler.noScaling,
                style: AppText.label.copyWith(color: Tokens.ink),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.title, style: AppText.bodyStrong),
                  const SizedBox(height: 2),
                  Text(step.body, style: AppText.body),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A highlighted aside under a lesson.
class TipBox extends StatelessWidget {
  final String text;
  final IconData icon;
  const TipBox(this.text, {super.key, this.icon = Icons.lightbulb_outline});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Tokens.brass.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(Tokens.radiusSm),
      border: Border.all(color: Tokens.brass.withValues(alpha: 0.5)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Icon(icon, size: 20, color: Tokens.brassText)),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: AppText.body)),
      ],
    ),
  );
}

class WelcomeView extends StatelessWidget {
  final WelcomePage page;
  const WelcomeView(this.page, {super.key});

  @override
  Widget build(BuildContext context) => TourPage(
    art: page.art,
    title: page.title,
    lead: page.lead,
    children: [for (var i = 0; i < page.points.length; i++) StepTile(i + 1, page.points[i])],
  );
}

String _stateLabel(PermState s) => switch (s) {
  PermState.notAsked => 'Not asked yet',
  PermState.granted => 'Allowed',
  PermState.denied => 'Not allowed',
  PermState.blocked => 'Blocked in phone settings',
};

/// One permission card: the explanation first, the system prompt only on Allow.
class PermissionView extends ConsumerStatefulWidget {
  final PermissionCardInfo info;
  const PermissionView(this.info, {super.key});

  @override
  ConsumerState<PermissionView> createState() => _PermissionViewState();
}

class _PermissionViewState extends ConsumerState<PermissionView> {
  PermState _state = PermState.notAsked;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final kind = widget.info.kind;
    if (kind != null) {
      ref.read(permissionServiceProvider).status(kind).then((s) {
        if (mounted) setState(() => _state = s);
      });
    }
  }

  Future<void> _allow() async {
    final kind = widget.info.kind;
    if (kind == null) return;
    setState(() => _busy = true);
    final s = await ref.read(permissionServiceProvider).request(kind);
    if (mounted) {
      setState(() {
        _state = s;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final granted = _state == PermState.granted;
    return TourPage(
      art: info.art,
      title: info.title,
      lead: info.kind == null
          ? 'Nothing to allow here, just good to know.'
          : 'Read this first. Android asks only after you tap Allow.',
      children: [
        _Section('Why we ask', info.why),
        _Section('What CardKeep never does', info.never),
        _Section('If you say no', info.ifNo),
        _Section('Change it later', info.later),
        if (info.kind != null) ...[
          const SizedBox(height: 4),
          Semantics(
            liveRegion: true,
            container: true,
            label: '${info.title} permission: ${_stateLabel(_state)}',
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Icon(
                    granted ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: granted ? const Color(0xFF2F9E5B) : Tokens.ink2,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_stateLabel(_state), style: AppText.bodyStrong)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_state == PermState.blocked) ...[
            Text(
              'Android will not ask again. You can still turn it on in the phone\'s settings, or carry on without it.',
              style: AppText.secondary,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => ref.read(permissionServiceProvider).openSettings(),
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open phone settings'),
            ),
          ] else if (!granted)
            FilledButton(
              onPressed: _busy ? null : _allow,
              child: Text(_state == PermState.denied ? 'Ask again' : 'Allow ${info.title.toLowerCase()}'),
            )
          else
            Text('Done. Tap Continue.', style: AppText.secondary),
          if (!granted)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Not now is fine: use Continue. You can allow it later.', style: AppText.secondary),
            ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  const _Section(this.title, this.body);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(
      container: true,
      label: '$title. $body',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Overline(title),
            const SizedBox(height: 3),
            Text(body, style: AppText.body),
          ],
        ),
      ),
    ),
  );
}

/// Set-up page 1: how it looks and how names and numbers read.
class SetupLookView extends ConsumerWidget {
  const SetupLookView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(settingsRepoProvider);
    final region = ref.watch(regionProvider).value ?? 'US';
    return TourPage(
      art: Art.setup,
      title: 'How should it look and read?',
      lead: 'Each choice applies at once. Change any of them later in Settings.',
      children: [
        const ThemePicker(),
        const SizedBox(height: 8),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              DropdownRow<bool>(
                title: 'Sort names by',
                subtitle: 'Used in lists and the A to Z strip',
                value: ref.watch(sortByFirstProvider).value ?? false,
                items: const [
                  DropdownMenuItem(value: false, child: Text('Last name')),
                  DropdownMenuItem(value: true, child: Text('First name')),
                ],
                onChanged: (v) => v == null ? null : settings.setSortByFirst(v),
              ),
              const Divider(indent: 16, endIndent: 16),
              DropdownRow<String>(
                title: 'Phone region',
                subtitle: 'For numbers written without a country code',
                value: phoneRegions.containsKey(region) ? region : null,
                hint: region,
                items: [for (final e in phoneRegions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => v == null ? null : settings.setRegion(v),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Set-up page 2: what CardKeep does with each card.
class SetupFeaturesView extends ConsumerWidget {
  const SetupFeaturesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(settingsRepoProvider);
    return TourPage(
      title: 'What should CardKeep do for you?',
      lead: 'Defaults are on. Switch off what you will not use.',
      children: [
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile(
                value: ref.watch(leadsEnabledProvider).value ?? true,
                activeThumbColor: Tokens.brass,
                onChanged: settings.setLeadsEnabled,
                title: Text('Lead ratings', style: AppText.body),
                subtitle: Text(
                  'Mark contacts Hot, Warm or Cold, and filter by them. Off hides them everywhere.',
                  style: AppText.secondary,
                ),
              ),
              const Divider(indent: 16, endIndent: 16),
              SwitchListTile(
                value: ref.watch(trackCareerProvider).value ?? true,
                activeThumbColor: Tokens.brass,
                onChanged: settings.setTrackCareer,
                title: Text('Career tracking', style: AppText.body),
                subtitle: Text(
                  'Suggests a job change when a new card or a bounced email shows someone moved. Each contact can opt out.',
                  style: AppText.secondary,
                ),
              ),
              const Divider(indent: 16, endIndent: 16),
              SwitchListTile(
                value: ref.watch(autoSaveCleanProvider).value ?? true,
                activeThumbColor: Tokens.brass,
                onChanged: settings.setAutoSaveClean,
                title: Text('Save clear cards automatically', style: AppText.body),
                subtitle: Text(
                  'In Batch, Pile and Sweep scanning, cards read with high confidence go straight to Contacts.',
                  style: AppText.secondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Overline('What that looks like (fictional examples)'),
        const SizedBox(height: 6),
        _ExampleRow(
          name: 'Dana Reyes, Halden Tooling',
          detail: 'Sharp photo, name and email found',
          outcome: ref.watch(autoSaveCleanProvider).value ?? true
              ? 'Goes straight to Contacts'
              : 'Waits in the Review queue',
          good: ref.watch(autoSaveCleanProvider).value ?? true,
        ),
        const _ExampleRow(
          name: 'Blurry photo, name unsure',
          detail: 'Low confidence, Blurry',
          outcome: 'Waits in the Review queue',
          good: false,
        ),
      ],
    );
  }
}

class _ExampleRow extends StatelessWidget {
  final String name;
  final String detail;
  final String outcome;
  final bool good;
  const _ExampleRow({required this.name, required this.detail, required this.outcome, required this.good});

  @override
  Widget build(BuildContext context) => Panel(
    margin: const EdgeInsets.symmetric(vertical: 4),
    padding: const EdgeInsets.all(12),
    child: Semantics(
      container: true,
      label: '$name. $detail. $outcome.',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Icon(
              good ? Icons.check_circle : Icons.hourglass_empty,
              color: good ? const Color(0xFF2F9E5B) : Tokens.amberFg,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: AppText.bodyStrong),
                  Text(detail, style: AppText.secondary),
                  const SizedBox(height: 4),
                  Text(outcome, style: AppText.body.copyWith(color: good ? const Color(0xFF2F9E5B) : Tokens.amberFg)),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Set-up page 3: the weekly backup, the only safety net.
class SetupBackupView extends ConsumerWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const SetupBackupView({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folder = ref.watch(appFolderLabelProvider).value ?? "CardKeep's private storage";
    return TourPage(
      art: Art.backup,
      title: 'Your safety net',
      lead: 'CardKeep keeps everything on this phone, so a backup is the only way back if something goes wrong.',
      children: [
        Panel(
          padding: EdgeInsets.zero,
          child: SwitchListTile(
            value: value,
            activeThumbColor: Tokens.brass,
            onChanged: onChanged,
            title: Text('Weekly backup on this phone', style: AppText.body),
            subtitle: Text(
              'When you open CardKeep and a week has passed, it saves a backup and keeps the newest four. On by default here.',
              style: AppText.secondary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _Section('Where they are kept', '$folder/backups (private to CardKeep; open them from Export and backup).'),
        const SizedBox(height: 8),
        const _Section(
          'Lock CardKeep (optional)',
          "Business cards hold other people's details. Turn on App lock to ask for your fingerprint, face or phone passcode when CardKeep opens. You can change it later in Settings, Privacy.",
        ),
        const Panel(padding: EdgeInsets.zero, child: AppLockTiles()),
        const SizedBox(height: 8),
        const TipBox(
          'A backup on the phone is lost with the phone. Every so often, use Export and backup, Back up now, and copy the file to a computer or a drive you trust.',
          icon: Icons.warning_amber_outlined,
        ),
      ],
    );
  }
}

/// One lesson page: animation, steps, tip, Try it.
class LessonView extends ConsumerWidget {
  final HelpArticle lesson;
  final int number;
  final int total;
  const LessonView(this.lesson, {super.key, required this.number, required this.total});

  @override
  Widget build(BuildContext context, WidgetRef ref) => TourPage(
    art: lesson.art,
    title: lesson.title,
    lead: total > 0 ? 'Lesson $number of $total. ${lesson.summary}' : lesson.summary,
    children: [
      for (var i = 0; i < lesson.steps.length; i++) StepTile(i + 1, lesson.steps[i]),
      if (lesson.tip != null) ...[TipBox(lesson.tip!), const SizedBox(height: 14)],
      if (lesson.tryRoute != null) TryItButton(lesson),
    ],
  );
}

/// "Try it": opens the real screen, with this lesson's coach mark forced once.
class TryItButton extends ConsumerWidget {
  final HelpArticle article;
  const TryItButton(this.article, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => OutlinedButton.icon(
    onPressed: () {
      ref.read(coachForceProvider.notifier).set(article.coachId);
      context.push(article.tryRoute!);
    },
    icon: const Icon(Icons.play_arrow_rounded),
    label: Text(article.tryLabel ?? 'Try it'),
  );
}
