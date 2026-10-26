import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/qr/frame_reader.dart';
import 'webcam_scan.dart';
import 'webcam_source.dart';

/// Builds the webcam. Tests replace it with a fake.
final webcamSourceFactoryProvider = Provider<WebcamSource Function()>((ref) => CameraWebcamSource.new);

/// How the webcam dialog ended.
enum WebcamQrOutcome {
  /// The PC paired with the phone.
  paired,

  /// "Paste instead".
  paste,

  /// Closed without pairing.
  cancelled,
}

/// Opens the webcam pairing dialog (S16.12). [onCode] pairs with the text of a
/// good code and returns the error, or null when it worked.
Future<WebcamQrOutcome> showWebcamQrDialog(
  BuildContext context, {
  required WebcamSource source,
  required PairCode onCode,
  Future<String?> Function(Uint8List bytes)? decode,
  Future<FrameReading> Function(Uint8List bytes)? read,
  Future<void> Function()? openCameraSettings,
}) async {
  final result = await showDialog<WebcamQrOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) => WebcamQrDialog(
      controller: WebcamScanController(source: source, onCode: onCode, decode: decode, read: read),
      openCameraSettings: openCameraSettings,
    ),
  );
  return result ?? WebcamQrOutcome.cancelled;
}

Future<void> _openWindowsCameraSettings() async {
  try {
    await launchUrl(Uri.parse('ms-settings:privacy-webcam'), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

/// The live camera picture with a frame to aim the phone at, and what is going on.
class WebcamQrDialog extends StatefulWidget {
  final WebcamScanController controller;
  final Future<void> Function()? openCameraSettings;
  const WebcamQrDialog({super.key, required this.controller, this.openCameraSettings});

  @override
  State<WebcamQrDialog> createState() => _WebcamQrDialogState();
}

class _WebcamQrDialogState extends State<WebcamQrDialog> {
  WebcamScanController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    c.start();
  }

  void _changed() {
    if (!mounted) return;
    if (c.state.phase == WebcamScanPhase.done) {
      Navigator.of(context).pop(WebcamQrOutcome.paired);
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    c.dispose(); // closes the camera
    super.dispose();
  }

  void _close(WebcamQrOutcome outcome) => Navigator.of(context).pop(outcome);

  @override
  Widget build(BuildContext context) {
    final s = c.state;
    return Dialog(
      backgroundColor: Tokens.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Scan the code on your phone', style: AppText.heading),
              const SizedBox(height: 6),
              // The picture and its words scroll on a short window; the buttons stay in view.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "On the phone open Sync to desktop and tap the code to make it big and bright. Hold the phone "
                        "40 to 60 cm (about 16 to 24 inches) from the camera, screen facing it, and keep it still. "
                        "If the picture looks blurry, move the phone slowly closer or further away.",
                        style: AppText.secondary,
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: AspectRatio(
                            aspectRatio: 4 / 3,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  const ColoredBox(color: Colors.black),
                                  if (s.cameraOn)
                                    FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: _preview(context)),
                                  if (s.cameraOn) const _AimBox(),
                                  if (!s.cameraOn) Center(child: _statusIcon(s)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(_message(s), style: AppText.body, key: const Key('webcam-status')),
                      ),
                      if (s.phase == WebcamScanPhase.scanning && s.looksBlurry) ...[
                        const SizedBox(height: 4),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            'Looks blurry. Move the phone slowly closer or further until the picture is sharp.',
                            style: AppText.bodyStrong,
                            key: const Key('webcam-blurry'),
                          ),
                        ),
                      ],
                      if (s.phase == WebcamScanPhase.busy && (s.message ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(s.message!, style: AppText.secondary),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  if (s.phase == WebcamScanPhase.denied)
                    OutlinedButton(
                      onPressed: widget.openCameraSettings ?? _openWindowsCameraSettings,
                      child: const Text('Open camera settings'),
                    ),
                  if (s.canRetry) FilledButton(onPressed: c.start, child: Text(_retryLabel(s))),
                  OutlinedButton(
                    onPressed: s.phase == WebcamScanPhase.pairing ? null : () => _close(WebcamQrOutcome.paste),
                    child: const Text('Paste instead'),
                  ),
                  TextButton(
                    onPressed: s.phase == WebcamScanPhase.pairing ? null : () => _close(WebcamQrOutcome.cancelled),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview(BuildContext context) => SizedBox(width: 640, height: 480, child: c.source.buildPreview(context));

  Widget _statusIcon(WebcamScanState s) {
    final icon = switch (s.phase) {
      WebcamScanPhase.noCamera => Icons.videocam_off,
      WebcamScanPhase.denied => Icons.lock_outline,
      WebcamScanPhase.busy => Icons.videocam_off,
      WebcamScanPhase.expired => Icons.timer_off_outlined,
      WebcamScanPhase.failed => Icons.error_outline,
      _ => null,
    };
    if (icon != null) return Icon(icon, size: 44, color: Colors.white70);
    return const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3));
  }

  String _retryLabel(WebcamScanState s) => switch (s.phase) {
    WebcamScanPhase.expired => 'Scan the new code',
    _ => 'Try again',
  };

  String _message(WebcamScanState s) => switch (s.phase) {
    WebcamScanPhase.starting => 'Starting the camera…',
    WebcamScanPhase.scanning => 'Looking for the code…',
    WebcamScanPhase.pairing => 'Got it. Pairing with the phone…',
    WebcamScanPhase.done => 'Paired.',
    WebcamScanPhase.noCamera =>
      'No camera found on this PC. Plug in a webcam and try again, or choose Paste instead and paste the code '
          'text from the phone.',
    WebcamScanPhase.denied =>
      'Windows is not letting CardKeep use the camera. Open camera settings and turn on "Let desktop apps access '
          'your camera", then try again.',
    WebcamScanPhase.busy =>
      'The camera is busy or did not start. Close other apps that use it (Teams, Zoom, the Camera app) and try again.',
    WebcamScanPhase.notCardKeep =>
      "That is a QR code, but not a CardKeep pairing code. Show the code on the phone's Sync to desktop screen.",
    WebcamScanPhase.newerVersion => s.message ?? 'That code is from a newer CardKeep. Update CardKeep first.',
    WebcamScanPhase.expired =>
      'That code expired or was already used. On the phone tap New code, then scan the new one.',
    WebcamScanPhase.failed => s.message ?? 'Pairing did not work. Try again.',
  };
}

/// Four corners to aim the phone at.
class _AimBox extends StatelessWidget {
  const _AimBox();

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _CornersPainter(Tokens.brassText.withAlpha(230))));
}

class _CornersPainter extends CustomPainter {
  final Color color;
  const _CornersPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final box = Rect.fromCenter(center: size.center(Offset.zero), width: size.width * 0.62, height: size.height * 0.8);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final len = box.shortestSide * 0.16;
    void corner(Offset p, double dx, double dy) {
      canvas.drawLine(p, p + Offset(dx * len, 0), paint);
      canvas.drawLine(p, p + Offset(0, dy * len), paint);
    }

    corner(box.topLeft, 1, 1);
    corner(box.topRight, -1, 1);
    corner(box.bottomLeft, 1, -1);
    corner(box.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(_CornersPainter old) => old.color != color;
}
