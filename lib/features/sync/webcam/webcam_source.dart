import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

/// How opening the webcam went.
enum WebcamOpen {
  ready,

  /// The PC has no camera.
  none,

  /// Windows camera privacy (or the user) refused the app.
  denied,

  /// Another app holds the camera, or it would not start.
  busy,
}

/// The PC's webcam, as the pairing scanner sees it: open it, take a still every
/// so often, show the preview, close it. The real one wraps the `camera` plugin;
/// tests use a fake (S16.12).
abstract class WebcamSource {
  /// Opens the first camera. [detail] on a failure is the plugin's own wording.
  Future<WebcamOpen> open();

  /// The text of the plugin error when [open] did not return [WebcamOpen.ready].
  String? get detail;

  /// One still as encoded picture bytes (jpeg), or null when none could be taken.
  Future<Uint8List?> captureFrame();

  /// The live picture, or an empty box when not open.
  Widget buildPreview(BuildContext context);

  /// Lets go of the camera. Safe to call twice.
  Future<void> close();
}

/// [WebcamSource] on the `camera` plugin (camera_windows). Windows has no image
/// stream, so a still is taken instead; the camera is released as soon as [close] runs.
class CameraWebcamSource implements WebcamSource {
  CameraController? _controller;
  String? _detail;
  bool _taking = false;

  /// True when the plugin accepted the auto-focus request (it does not on Windows today).
  bool focusRequested = false;

  @override
  String? get detail => _detail;

  @override
  Future<WebcamOpen> open() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return WebcamOpen.none;
      // 1280x720: sharp enough to read a QR across the desk, and many webcams focus
      // and expose better, and faster, at 720p than at their top 1080p mode.
      final controller = CameraController(cameras.first, ResolutionPreset.high, enableAudio: false);
      _controller = controller;
      await controller.initialize();
      // Ask for continuous auto-focus and exposure. camera_windows does not
      // implement either yet (it throws), and the webcam's own driver then does what
      // it does; so each request is allowed to fail.
      try {
        await controller.setFocusMode(FocusMode.auto);
        focusRequested = true;
      } catch (_) {}
      try {
        await controller.setExposureMode(ExposureMode.auto);
      } catch (_) {}
      return WebcamOpen.ready;
    } on CameraException catch (e) {
      _detail = e.description ?? e.code;
      await close();
      final code = e.code.toLowerCase();
      if (code.contains('denied') || code.contains('permission') || code.contains('restricted')) {
        return WebcamOpen.denied;
      }
      if (code.contains('nocamera') || code.contains('no_available') || code.contains('notfound')) {
        return WebcamOpen.none;
      }
      return WebcamOpen.busy;
    } catch (e) {
      _detail = '$e';
      await close();
      return WebcamOpen.busy;
    }
  }

  @override
  Future<Uint8List?> captureFrame() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _taking) return null;
    _taking = true;
    try {
      final shot = await controller.takePicture();
      final file = File(shot.path);
      final bytes = await file.readAsBytes();
      // takePicture leaves a file in the temp folder: do not pile them up.
      unawaited(file.delete().then((_) {}, onError: (_) {}));
      return bytes;
    } catch (_) {
      return null;
    } finally {
      _taking = false;
    }
  }

  @override
  Widget buildPreview(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return const SizedBox.shrink();
    return CameraPreview(controller);
  }

  @override
  Future<void> close() async {
    final controller = _controller;
    _controller = null;
    try {
      await controller?.dispose();
    } catch (_) {}
  }
}
