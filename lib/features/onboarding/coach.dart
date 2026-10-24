import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import 'onboarding_gate.dart';
import 'onboarding_providers.dart';

/// One tooltip of a coach-mark sequence: which [CoachTarget] to light up and
/// what to say.
class CoachStep {
  final String targetId;
  final String title;
  final String body;
  const CoachStep(this.targetId, this.title, this.body);
}

final _targets = <String, GlobalKey>{};

/// Marks a widget a coach mark can point at. Put it around the thing, and name
/// it in a [CoachStep] by [id].
class CoachTarget extends StatefulWidget {
  final String id;
  final Widget child;
  const CoachTarget({super.key, required this.id, required this.child});

  @override
  State<CoachTarget> createState() => _CoachTargetState();
}

class _CoachTargetState extends State<CoachTarget> {
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    _targets[widget.id] = _key;
  }

  @override
  void didUpdateWidget(CoachTarget old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      if (_targets[old.id] == _key) _targets.remove(old.id);
      _targets[widget.id] = _key;
    }
  }

  @override
  void dispose() {
    if (_targets[widget.id] == _key) _targets.remove(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(key: _key, child: widget.child);
}

Rect? _rectOf(String id) {
  final ctx = _targets[id]?.currentContext;
  final box = ctx?.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  final topLeft = box.localToGlobal(Offset.zero);
  return topLeft & box.size;
}

/// Shows [steps] one after another over the current screen. Completes with
/// true if at least one step was shown (targets that are not on screen are
/// skipped), false if none could be.
Future<bool> runCoach(BuildContext context, List<CoachStep> steps) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final done = Completer<bool>();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CoachOverlay(
      steps: steps,
      onClose: (shown) {
        entry.remove();
        if (!done.isCompleted) done.complete(shown);
      },
    ),
  );
  overlay.insert(entry);
  return done.future;
}

/// Wraps a screen's body. The first time the screen opens (and tips are on, or
/// "Try it" asked for this tip), it shows [steps] once, then remembers.
class CoachScope extends ConsumerStatefulWidget {
  final String tipId;
  final List<CoachStep> steps;
  final Widget child;

  /// Lets a screen hold the tip until it is ready (for example a scanner mode).
  final bool enabled;
  final Duration delay;
  const CoachScope({
    super.key,
    required this.tipId,
    required this.steps,
    required this.child,
    this.enabled = true,
    this.delay = const Duration(milliseconds: 700),
  });

  @override
  ConsumerState<CoachScope> createState() => _CoachScopeState();
}

class _CoachScopeState extends ConsumerState<CoachScope> {
  Timer? _timer;
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(CoachScope old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !old.enabled) _arm();
  }

  void _arm() {
    if (!widget.enabled) return;
    _tried = false;
    _timer?.cancel();
    _timer = Timer(widget.delay, _maybeShow);
  }

  Future<void> _maybeShow() async {
    if (!mounted || _tried || !widget.enabled) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      // Covered by another screen: try again shortly.
      _timer = Timer(widget.delay, _maybeShow);
      return;
    }
    final settings = ref.read(settingsRepoProvider);
    final forced = ref.read(coachForceProvider);
    final show = shouldShowTip(
      widget.tipId,
      tipsEnabled: await settings.tipsEnabled(),
      seen: await settings.tipsSeen(),
      forced: forced,
    );
    if (!mounted || !show) return;
    _tried = true;
    if (forced == widget.tipId) ref.read(coachForceProvider.notifier).set(null);
    final shown = await runCoach(context, widget.steps);
    if (shown) await settings.markTipSeen(widget.tipId);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _CoachOverlay extends StatefulWidget {
  final List<CoachStep> steps;
  final void Function(bool shown) onClose;
  const _CoachOverlay({required this.steps, required this.onClose});

  @override
  State<_CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends State<_CoachOverlay> {
  int _i = -1;
  bool _any = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _advance());
  }

  /// Moves to the next step whose target is on screen; closes when none is left.
  void _advance() {
    if (!mounted) return;
    var j = _i + 1;
    while (j < widget.steps.length && _rectOf(widget.steps[j].targetId) == null) {
      j++;
    }
    if (j >= widget.steps.length) {
      widget.onClose(_any);
      return;
    }
    setState(() {
      _i = j;
      _any = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_i < 0) return const SizedBox.shrink();
    final step = widget.steps[_i];
    final rect = _rectOf(step.targetId);
    if (rect == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _advance());
      return const SizedBox.shrink();
    }
    final size = MediaQuery.sizeOf(context);
    final hole = RRect.fromRectAndRadius(rect.inflate(8), const Radius.circular(18));
    final below = rect.center.dy < size.height * 0.5;
    final last = widget.steps.indexWhere((s) => _rectOf(s.targetId) != null, _i + 1) < 0;
    final reduce = MediaQuery.of(context).disableAnimations;
    return Material(
      type: MaterialType.transparency,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: reduce ? 1 : 0, end: 1),
        duration: const Duration(milliseconds: 220),
        builder: (context, t, _) => Opacity(
          opacity: t,
          child: Stack(
            children: [
              // Absorbs taps so the screen underneath is not used mid-tip.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: CustomPaint(painter: _SpotlightPainter(hole, Tokens.brass)),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                top: below ? hole.bottom + 12 : null,
                bottom: below ? null : size.height - hole.top + 12,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: size.height * 0.5),
                  child: Semantics(
                    container: true,
                    liveRegion: true,
                    label: 'Tip ${_i + 1} of ${widget.steps.length}: ${step.title}. ${step.body}',
                    child: Material(
                      color: Tokens.surface,
                      elevation: 6,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Tokens.radius),
                        side: BorderSide(color: Tokens.hairline),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 12, 8),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ExcludeSemantics(child: Text(step.title, style: AppText.heading)),
                              const SizedBox(height: 6),
                              ExcludeSemantics(child: Text(step.body, style: AppText.body)),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  if (widget.steps.length > 1)
                                    Text('${_i + 1} of ${widget.steps.length}', style: AppText.secondary),
                                  const Spacer(),
                                  if (!last)
                                    TextButton(onPressed: () => widget.onClose(true), child: const Text('Skip')),
                                  FilledButton(
                                    onPressed: last ? () => widget.onClose(true) : _advance,
                                    child: Text(last ? 'Got it' : 'Next'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final RRect hole;
  final Color ring;
  _SpotlightPainter(this.hole, this.ring);

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(hole));
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha: 0.72));
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = ring,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.hole != hole || old.ring != ring;
}
