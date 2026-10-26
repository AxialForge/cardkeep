import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screen_brightness/screen_brightness.dart';

/// Turns the screen all the way up and puts it back. Tests give a fake, because
/// the real one talks to the phone.
abstract class QrBrightness {
  Future<void> max();
  Future<void> restore();
}

/// [QrBrightness] on the screen_brightness plugin. Failing to change the
/// brightness is never a reason to stop showing the code.
class PluginQrBrightness implements QrBrightness {
  const PluginQrBrightness();

  @override
  Future<void> max() async {
    try {
      await ScreenBrightness().setApplicationScreenBrightness(1.0);
    } catch (_) {}
  }

  @override
  Future<void> restore() async {
    try {
      await ScreenBrightness().resetApplicationScreenBrightness();
    } catch (_) {}
  }
}

/// The pairing code as large as the screen allows, on plain white at full
/// brightness, so a PC webcam can read it from across the desk (S16.12). Tap
/// anywhere to close; the brightness goes back to what it was.
Future<void> showQrFullScreen(
  BuildContext context, {
  required String data,
  QrBrightness brightness = const PluginQrBrightness(),
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      fullscreenDialog: true,
      pageBuilder: (_, _, _) => QrFullScreen(data: data, brightness: brightness),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
  );
}

class QrFullScreen extends StatefulWidget {
  final String data;
  final QrBrightness brightness;
  const QrFullScreen({super.key, required this.data, this.brightness = const PluginQrBrightness()});

  @override
  State<QrFullScreen> createState() => _QrFullScreenState();
}

class _QrFullScreenState extends State<QrFullScreen> {
  @override
  void initState() {
    super.initState();
    widget.brightness.max();
  }

  @override
  void dispose() {
    widget.brightness.restore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final side = (size.shortestSide - 40).clamp(160.0, 640.0);
    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        key: const Key('qr-fullscreen'),
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QrImageView(
                    data: widget.data,
                    size: side,
                    backgroundColor: Colors.white,
                    semanticsLabel: 'Pairing code for your PC, enlarged',
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      "Hold this towards your PC's camera, 40 to 60 cm away, and keep it still. Tap anywhere to close.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black87, fontSize: 16, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
