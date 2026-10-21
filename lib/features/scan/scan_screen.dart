import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../scan/card_detector.dart';
import '../../scan/geometry.dart';
import '../../scan/quality.dart';
import '../../scan/scan_pipeline.dart';
import '../../scan/scan_worker.dart';
import 'scan_review.dart';

/// Scan screen (mockup Scan.dc.html): live outline, one hint at a time,
/// auto-capture when the card is clean and steady, manual shutter always.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});
  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

enum _CamState { starting, ready, denied, deniedForever, noCamera, error }

class _ScanScreenState extends ConsumerState<ScanScreen> with WidgetsBindingObserver, RouteAware {
  CameraController? _cam;
  _CamState _state = _CamState.starting;
  String? _error;
  _Mode _mode = _Mode.single;
  bool _waitForClear = false; // batch: the last card must leave the frame first
  bool _torch = false;
  bool _busy = false; // capturing / processing a still
  bool _analysing = false;
  DateTime _lastFrame = DateTime(0);
  Detection? _live;
  Quad? _lastQuad;
  Size _frameSize = Size.zero; // portrait, detection space
  bool _exposureLocked = false;
  bool _starting = false; // the permission dialog pauses/resumes the app mid-start
  bool _picking = false; // the photo picker pauses/resumes the app; keep the camera as is
  bool _covered = false; // another screen (review, queue, crop) is on top: camera off
  final _auto = AutoCapture();

  /// When set, the next capture is the back of this card.
  ScanHandoff? _awaitingBackOf;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) routeObserver.subscribe(this, route);
  }

  // Another screen opened on top: free the camera. Screens like review replace
  // themselves (pushReplacement), so never wait on a push to finish; react to
  // coming back on top instead.
  @override
  void didPushNext() {
    _covered = true;
    final c = _cam;
    _cam = null;
    _live = null;
    _busy = false;
    c?.dispose();
  }

  @override
  void didPopNext() {
    _covered = false;
    if (mounted) _start();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _cam?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final c = _cam;
    if (_starting || _picking || _covered) return; // permission dialog, picker, or another screen on top
    if (s == AppLifecycleState.inactive || s == AppLifecycleState.paused) {
      _cam = null;
      c?.dispose();
    } else if (s == AppLifecycleState.resumed && c == null) {
      _start();
    }
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    try {
      await _startCamera();
    } finally {
      _starting = false;
    }
  }

  Future<void> _startCamera() async {
    await _cam?.dispose();
    _cam = null;
    setState(() => _state = _CamState.starting);
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isPermanentlyDenied || status.isRestricted) return setState(() => _state = _CamState.deniedForever);
    if (!status.isGranted) return setState(() => _state = _CamState.denied);
    try {
      final cams = await availableCameras();
      final back = cams.where((c) => c.lensDirection == CameraLensDirection.back).firstOrNull ?? cams.firstOrNull;
      if (back == null) return setState(() => _state = _CamState.noCamera);
      // Max resolution so the rectified card reaches 1400 px; frames are
      // subsampled before detection, so preview analysis stays cheap.
      final c = CameraController(
        back,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await c.initialize();
      await c.setFocusMode(FocusMode.auto);
      await c.setFlashMode(FlashMode.off);
      if (!mounted) {
        await c.dispose();
        return;
      }
      _cam = c;
      _torch = false;
      await c.startImageStream(_onFrame);
      setState(() => _state = _CamState.ready);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = e.code.contains('AccessDenied') ? _CamState.denied : _CamState.error;
        _error = e.description;
      });
    }
  }

  // ---------------------------------------------------------------- live

  void _onFrame(CameraImage img) {
    final cam = _cam; // null once the camera was released (picker, background)
    if (cam == null) return;
    final now = DateTime.now();
    if (_busy || _analysing || now.difference(_lastFrame).inMilliseconds < 180) return;
    _analysing = true;
    _lastFrame = now;
    final frame = _portraitGray(img, cam.description.sensorOrientation);
    compute(detect, frame)
        .then((d) {
          if (!mounted || _busy) return;
          _frameSize = Size(frame.width.toDouble(), frame.height.toDouble());
          final q = d.card;
          final steady = q != null && _lastQuad != null && sameQuad(q, _lastQuad!, frame.width * Gates.steadyTolerance);
          _lastQuad = q;
          if (q != null && !_exposureLocked) {
            _exposureLocked = true;
            _cam?.setExposureMode(ExposureMode.locked).catchError((_) {});
          } else if (q == null && _exposureLocked) {
            _exposureLocked = false;
            _cam?.setExposureMode(ExposureMode.auto).catchError((_) {});
          }
          setState(() => _live = d);
          if (q == null) _waitForClear = false;
          if (_mode != _Mode.pile &&
              !_waitForClear &&
              _auto.update(issues: d.issues, steady: steady, now: DateTime.now())) {
            HapticFeedback.mediumImpact();
            _capture();
          }
        })
        .whenComplete(() => _analysing = false);
  }

  /// Y plane -> portrait greyscale, subsampled to ~640 px on the long edge.
  static GrayFrame _portraitGray(CameraImage img, int sensorOrientation) {
    final y = img.planes.first;
    final w = img.width, h = img.height, stride = y.bytesPerRow;
    final step = (w > h ? w : h) ~/ 640 + 1;
    final ow = h ~/ step, oh = w ~/ step; // rotated to portrait
    final out = Uint8List(ow * oh);
    final src = y.bytes;
    var i = 0;
    final cw = sensorOrientation == 270;
    for (var v = 0; v < oh; v++) {
      for (var u = 0; u < ow; u++) {
        final sx = cw ? (w - 1 - v * step) : v * step;
        final sy = cw ? u * step : (h - 1 - u * step);
        out[i++] = src[sy * stride + sx];
      }
    }
    return GrayFrame(out, ow, oh);
  }

  // ------------------------------------------------------------- capture

  Future<void> _capture() async {
    final c = _cam;
    if (c == null || _busy) return;
    final worker = ref.read(scanWorkerProvider.notifier);
    if (_mode != _Mode.single && _awaitingBackOf == null) {
      // Batch / pile: hand the photo to the background reader and keep going.
      if (worker.full) {
        showMessage(context, 'Still reading ${ScanWorker.maxQueued} cards. One moment.');
        return;
      }
      setState(() => _busy = true);
      try {
        final shot = await c.takePicture();
        worker.add(ScanJob(await shot.readAsBytes(), pile: _mode == _Mode.pile));
        unawaited(HapticFeedback.lightImpact());
        _waitForClear = true; // don't re-shoot the same card
      } on CameraException catch (e) {
        if (mounted) showMessage(context, 'Capture failed: ${e.description ?? e.code}');
      } finally {
        _auto.reset();
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    setState(() => _busy = true);
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
      final shot = await c.takePicture();
      await _readOne(await shot.readAsBytes());
    } on CameraException catch (e) {
      if (mounted) showMessage(context, 'Capture failed: ${e.description ?? e.code}');
    } catch (e, st) {
      // Never loop silently: the photo is kept in the queue, say what failed.
      debugPrint('Card read failed: $e\n$st');
      if (mounted) showMessage(context, 'Could not read that card. Try again, or pick the photo from the gallery.');
    } finally {
      await _resume();
    }
  }

  Future<void> _resume() async {
    _auto.reset();
    _lastQuad = null;
    _live = null;
    if (!mounted || _covered) return;
    setState(() => _busy = false);
    final c = _cam;
    if (c != null && c.value.isInitialized && !c.value.isStreamingImages) {
      try {
        await c.startImageStream(_onFrame);
      } on CameraException {
        // Camera went away (backgrounded); lifecycle handler restarts it.
      }
    }
  }

  Future<void> _fromGallery() async {
    // Release the camera before the picker covers us: Android may tear our
    // surface down while it is open, and a live camera stream then crashes the
    // engine ("FlutterJNI is not attached"). It restarts afterwards.
    _picking = true;
    final cam = _cam;
    _cam = null;
    _live = null;
    await cam?.dispose();
    final List<XFile> files;
    try {
      files = await ImagePicker().pickMultiImage(requestFullMetadata: false);
    } finally {
      _picking = false;
    }
    if (!mounted) return;
    if (files.isEmpty) return _start();
    try {
      if (files.length == 1 && (_mode == _Mode.single || _awaitingBackOf != null)) {
        setState(() => _busy = true);
        await _readOne(await files.single.readAsBytes());
      } else {
        final worker = ref.read(scanWorkerProvider.notifier);
        for (final f in files) {
          worker.add(ScanJob(await f.readAsBytes(), pile: _mode == _Mode.pile || files.length == 1));
        }
        if (mounted) unawaited(context.push('/queue'));
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Could not read that photo: $e');
    } finally {
      _busy = false;
      if (mounted && !_covered) await _start();
    }
  }

  /// One card, read right away: stored in the queue first (so it's never
  /// lost), then reviewed.
  Future<void> _readOne(Uint8List jpeg) async {
    final pipeline = await ref.read(scanPipelineProvider.future);
    final queue = await ref.read(cardQueueProvider.future);
    final sides = await pipeline.process(jpeg);
    if (!mounted || sides.isEmpty) return;
    final back = _awaitingBackOf;
    if (back != null) {
      setState(() => _awaitingBackOf = null);
      await queue.setBack(back.cardId, back.front, sides.first);
      if (mounted) {
        unawaited(
          context.push(
            '/contact/new',
            extra: ScanHandoff(cardId: back.cardId, front: back.front, back: sides.first),
          ),
        );
      }
      return;
    }
    final id = await queue.enqueue(sides.first);
    if (mounted) await _reviewOne(ScanHandoff(cardId: id, front: sides.first));
  }

  /// Bottom sheet after a single capture: review, add back, crop, or retake.
  Future<void> _reviewOne(ScanHandoff card) async {
    final action = await showCaptureSheet(context, card.front);
    if (!mounted) return;
    final queue = await ref.read(cardQueueProvider.future);
    if (!mounted) return;
    switch (action) {
      case CaptureAction.use:
        unawaited(context.push('/contact/new', extra: card));
      case CaptureAction.addBack:
        setState(() => _awaitingBackOf = card);
        showMessage(context, 'Now photograph the back of the card');
      case CaptureAction.crop:
        final redone = await context.push<ScannedSide>('/scan/crop', extra: card.front);
        if (redone != null && mounted) {
          await queue.discard(card.cardId);
          final id = await queue.enqueue(redone);
          if (mounted) await _reviewOne(ScanHandoff(cardId: id, front: redone));
        }
      case CaptureAction.retake:
        await queue.discard(card.cardId);
      case null:
        showMessage(context, 'Kept in the review queue');
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: switch (_state) {
          _CamState.ready when _cam != null => _camera(),
          _CamState.ready => Center(
            child: Text(_busy ? 'Reading cards…' : '', style: AppText.bodyStrong.copyWith(color: Colors.white)),
          ),
          _CamState.starting => const Center(child: CircularProgressIndicator()),
          _CamState.denied => _blocked(
            'CardKeep needs the camera to read cards',
            'Photos stay on this phone. You can also pick card photos from your gallery.',
            FilledButton(onPressed: _start, child: const Text('Allow camera')),
          ),
          _CamState.deniedForever => _blocked(
            'Camera access is off',
            'Turn on Camera for CardKeep in your phone settings, or pick card photos from your gallery.',
            const FilledButton(onPressed: openAppSettings, child: Text('Open settings')),
          ),
          _CamState.noCamera => _blocked('No camera found', 'You can still pick card photos from your gallery.', null),
          _CamState.error => _blocked(
            'The camera could not start',
            _error ?? '',
            FilledButton(onPressed: _start, child: const Text('Try again')),
          ),
        },
      ),
    );
  }

  Widget _blocked(String title, String message, Widget? action) => SafeArea(
    child: Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: BackButton(color: Tokens.onStrong),
        ),
        Expanded(
          child: Container(
            color: Tokens.ground,
            child: EmptyState(
              icon: Icons.no_photography_outlined,
              title: title,
              message: message,
              action: Column(
                children: [
                  ?action,
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _fromGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Pick photos'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _camera() {
    final c = _cam!;
    final issues = _live?.issues ?? const [QualityIssue.noCard];
    final hint = _awaitingBackOf != null && issues.isNotEmpty && issues.first == QualityIssue.noCard
        ? 'Turn the card over'
        : issues.isEmpty
        ? switch (_mode) {
            _Mode.pile => 'Tap the shutter to capture all cards',
            _Mode.batch when _waitForClear => 'Got it. Next card',
            _ => 'Hold steady…',
          }
        : issues.first.hint;
    final previewAspect = 1 / c.value.aspectRatio; // portrait
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: previewAspect,
            child: GestureDetector(
              onTapUp: (d) {
                final box = context.findRenderObject() as RenderBox?;
                if (box == null) return;
                final s = box.size;
                c.setFocusPoint(Offset(d.localPosition.dx / s.width, d.localPosition.dy / s.height)).catchError((_) {});
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(c),
                  CustomPaint(painter: _OutlinePainter(_live, _frameSize, _mode == _Mode.pile)),
                ],
              ),
            ),
          ),
        ),
        // Top bar
        Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _RoundIcon(icon: Icons.close, label: 'Close', onTap: () => context.pop()),
                  const Spacer(),
                  _ModeSwitch(
                    mode: _mode,
                    onChanged: _awaitingBackOf != null ? null : (m) => setState(() => _mode = m),
                  ),
                  const Spacer(),
                  _RoundIcon(
                    icon: _torch ? Icons.flash_on : Icons.flash_off,
                    label: _torch ? 'Torch off' : 'Torch on',
                    onTap: () async {
                      _torch = !_torch;
                      await c.setFlashMode(_torch ? FlashMode.torch : FlashMode.off).catchError((_) {});
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        // Hint + controls
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _QueueChip(),
                  if (_awaitingBackOf != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Pill('BACK SIDE', bg: Tokens.action, fg: Tokens.onAction),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(99)),
                    child: Text(
                      _busy ? 'Reading card…' : hint,
                      style: AppText.bodyStrong.copyWith(color: Colors.white),
                      semanticsLabel: 'Hint: ${_busy ? 'Reading card' : hint}',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _RoundIcon(
                        icon: Icons.photo_library_outlined,
                        label: 'Pick photos',
                        onTap: _busy ? null : _fromGallery,
                      ),
                      _Shutter(busy: _busy && _mode == _Mode.single, onTap: _capture),
                      _awaitingBackOf != null
                          ? _RoundIcon(
                              icon: Icons.skip_next,
                              label: 'Skip back side',
                              onTap: () async {
                                final f = _awaitingBackOf!;
                                setState(() => _awaitingBackOf = null);
                                unawaited(context.push('/contact/new', extra: f));
                              },
                            )
                          : const SizedBox(width: 52),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OutlinePainter extends CustomPainter {
  final Detection? d;
  final Size frame;
  final bool pile;
  _OutlinePainter(this.d, this.frame, this.pile);

  @override
  void paint(Canvas canvas, Size size) {
    final det = d;
    if (det == null || frame == Size.zero) return;
    final sx = size.width / frame.width, sy = size.height / frame.height;
    final quads = pile ? det.cards : [?det.card];
    for (final q in quads) {
      final path = Path()..moveTo(q.tl.x * sx, q.tl.y * sy);
      for (final p in [q.tr, q.br, q.bl]) {
        path.lineTo(p.x * sx, p.y * sy);
      }
      path.close();
      final ok = det.clean || pile;
      canvas.drawPath(path, Paint()..color = (ok ? Tokens.brandOrange : Colors.white).withValues(alpha: 0.18));
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = ok ? Tokens.brandOrange : Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_OutlinePainter old) => old.d != d || old.pile != pile;
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _RoundIcon({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(icon, color: Colors.white, semanticLabel: label),
        ),
      ),
    ),
  );
}

class _Shutter extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _Shutter({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Take photo',
    child: GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        width: 78,
        height: 78,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: Container(
          decoration: BoxDecoration(shape: BoxShape.circle, color: busy ? Colors.white38 : Tokens.brandOrange),
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                )
              : null,
        ),
      ),
    ),
  );
}

enum _Mode { single, batch, pile }

class _ModeSwitch extends StatelessWidget {
  final _Mode mode;
  final ValueChanged<_Mode>? onChanged;
  const _ModeSwitch({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, _Mode value) => Semantics(
      button: true,
      selected: mode == value,
      label: '$label mode',
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: mode == value ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(99),
          ),
          child: ExcludeSemantics(
            child: Text(
              label,
              style: AppText.label.copyWith(color: mode == value ? Colors.black : Colors.white, fontSize: 13),
            ),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [seg('One card', _Mode.single), seg('Batch', _Mode.batch), seg('Pile', _Mode.pile)],
      ),
    );
  }
}

/// "3 reading · 5 to review": opens the review queue.
class _QueueChip extends ConsumerWidget {
  const _QueueChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = ref.watch(scanWorkerProvider).reading;
    final waiting = ref.watch(queueProvider).value?.length ?? 0;
    if (reading == 0 && waiting == 0) return const SizedBox.shrink();
    final text = [if (reading > 0) '$reading reading', if (waiting > 0) '$waiting to review'].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Tokens.brandOrange,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: () => context.push('/queue'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (reading > 0)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                  ),
                Text(text, style: AppText.label.copyWith(color: Colors.white, fontSize: 13)),
                const Icon(Icons.chevron_right, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
