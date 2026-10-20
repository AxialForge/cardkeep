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
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../scan/card_detector.dart';
import '../../scan/geometry.dart';
import '../../scan/quality.dart';
import '../../scan/scan_pipeline.dart';
import 'scan_review.dart';

/// Scan screen (mockup Scan.dc.html): live outline, one hint at a time,
/// auto-capture when the card is clean and steady, manual shutter always.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});
  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

enum _CamState { starting, ready, denied, deniedForever, noCamera, error }

class _ScanScreenState extends ConsumerState<ScanScreen> with WidgetsBindingObserver {
  CameraController? _cam;
  _CamState _state = _CamState.starting;
  String? _error;
  bool _pile = false;
  bool _torch = false;
  bool _busy = false; // capturing / processing a still
  bool _analysing = false;
  DateTime _lastFrame = DateTime(0);
  Detection? _live;
  Quad? _lastQuad;
  Size _frameSize = Size.zero; // portrait, detection space
  bool _exposureLocked = false;
  final _auto = AutoCapture();

  /// When set, the next capture is the back of this card.
  ScannedSide? _awaitingBackOf;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cam?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final c = _cam;
    if (s == AppLifecycleState.inactive || s == AppLifecycleState.paused) {
      _cam = null;
      c?.dispose();
    } else if (s == AppLifecycleState.resumed && c == null) {
      _start();
    }
  }

  Future<void> _start() async {
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
    final now = DateTime.now();
    if (_busy || _analysing || now.difference(_lastFrame).inMilliseconds < 180) return;
    _analysing = true;
    _lastFrame = now;
    final frame = _portraitGray(img, _cam!.description.sensorOrientation);
    compute(detect, frame)
        .then((d) {
          if (!mounted || _busy) return;
          _frameSize = Size(frame.width.toDouble(), frame.height.toDouble());
          final q = d.card;
          final steady = q != null && _lastQuad != null && sameQuad(q, _lastQuad!, frame.width * 0.02);
          _lastQuad = q;
          if (q != null && !_exposureLocked) {
            _exposureLocked = true;
            _cam?.setExposureMode(ExposureMode.locked).catchError((_) {});
          } else if (q == null && _exposureLocked) {
            _exposureLocked = false;
            _cam?.setExposureMode(ExposureMode.auto).catchError((_) {});
          }
          setState(() => _live = d);
          if (!_pile && _auto.update(clean: d.clean, steady: steady, now: DateTime.now())) {
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
    setState(() => _busy = true);
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
      final shot = await c.takePicture();
      await _process(await shot.readAsBytes());
    } on CameraException catch (e) {
      if (mounted) showMessage(context, 'Capture failed: ${e.description ?? e.code}');
    } finally {
      await _resume();
    }
  }

  Future<void> _resume() async {
    _auto.reset();
    _lastQuad = null;
    _live = null;
    if (!mounted) return;
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
    final files = await ImagePicker().pickMultiImage(requestFullMetadata: false);
    if (files.isEmpty || !mounted) return;
    setState(() => _busy = true);
    if (_cam?.value.isStreamingImages ?? false) await _cam!.stopImageStream();
    try {
      final sides = <ScannedSide>[];
      final pipeline = await ref.read(scanPipelineProvider.future);
      for (final f in files) {
        sides.addAll(await pipeline.process(await f.readAsBytes(), pile: _pile || files.length == 1));
      }
      if (!mounted) return;
      if (sides.length == 1 && _awaitingBackOf == null) {
        await _reviewOne(sides.single);
      } else if (sides.length == 1) {
        await _finishBack(sides.single);
      } else {
        await context.push('/scan/results', extra: sides);
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Could not read that photo: $e');
    } finally {
      await _resume();
    }
  }

  Future<void> _process(Uint8List jpeg) async {
    final pipeline = await ref.read(scanPipelineProvider.future);
    final sides = await pipeline.process(jpeg, pile: _pile);
    if (!mounted || sides.isEmpty) return;
    if (_awaitingBackOf != null) return _finishBack(sides.first);
    if (sides.length > 1) {
      await context.push('/scan/results', extra: sides);
      return;
    }
    await _reviewOne(sides.single);
  }

  /// Bottom sheet after a single capture: keep, add back, crop, or retake.
  Future<void> _reviewOne(ScannedSide side) async {
    final action = await showCaptureSheet(context, side);
    if (!mounted) return;
    switch (action) {
      case CaptureAction.use:
        await context.push('/contact/new', extra: ScanHandoff(front: side));
      case CaptureAction.addBack:
        setState(() => _awaitingBackOf = side);
        showMessage(context, 'Now photograph the back of the card');
      case CaptureAction.crop:
        final redone = await context.push<ScannedSide>('/scan/crop', extra: side);
        if (redone != null && mounted) await _reviewOne(redone);
      case CaptureAction.retake:
      case null:
        break;
    }
  }

  Future<void> _finishBack(ScannedSide back) async {
    final front = _awaitingBackOf!;
    setState(() => _awaitingBackOf = null);
    await context.push(
      '/contact/new',
      extra: ScanHandoff(front: front, back: back),
    );
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: switch (_state) {
          _CamState.ready => _camera(),
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
        ? (_pile ? 'Tap the shutter to capture all cards' : 'Hold steady…')
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
                  CustomPaint(painter: _OutlinePainter(_live, _frameSize, _pile)),
                ],
              ),
            ),
          ),
        ),
        // Top bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _RoundIcon(icon: Icons.close, label: 'Close', onTap: () => context.pop()),
                const Spacer(),
                _ModeSwitch(pile: _pile, onChanged: (v) => setState(() => _pile = v)),
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
        // Hint + controls
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                      _Shutter(busy: _busy, onTap: _capture),
                      _awaitingBackOf != null
                          ? _RoundIcon(
                              icon: Icons.skip_next,
                              label: 'Skip back side',
                              onTap: () async {
                                final f = _awaitingBackOf!;
                                setState(() => _awaitingBackOf = null);
                                await context.push('/contact/new', extra: ScanHandoff(front: f));
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

class _ModeSwitch extends StatelessWidget {
  final bool pile;
  final ValueChanged<bool> onChanged;
  const _ModeSwitch({required this.pile, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool on, bool value) => GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: on ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(label, style: AppText.label.copyWith(color: on ? Colors.black : Colors.white, fontSize: 13)),
      ),
    );
    return Semantics(
      label: 'Scan mode',
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(99)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [seg('One card', !pile, false), seg('Several', pile, true)],
        ),
      ),
    );
  }
}
