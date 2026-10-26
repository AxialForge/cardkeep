import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/qr/frame_reader.dart';
import '../../../core/sync/change_set.dart';
import '../../../core/sync/net/pairing.dart';
import '../../../core/sync/net/sync_client.dart';
import 'webcam_source.dart';

/// What the webcam pairing dialog is doing (S16.12).
enum WebcamScanPhase {
  /// Opening the camera.
  starting,

  /// Looking for a code.
  scanning,

  /// A good code was read; the camera is closed and the PC is pairing.
  pairing,

  /// Paired. The dialog closes.
  done,

  /// No camera on this PC.
  noCamera,

  /// Windows camera privacy (or the user) refused the app.
  denied,

  /// Another app holds the camera, or it did not start.
  busy,

  /// A QR code was read but it is not a CardKeep code. Keeps looking.
  notCardKeep,

  /// The code is from a newer CardKeep. Keeps looking.
  newerVersion,

  /// The phone said the code expired or was used. The camera is closed.
  expired,

  /// Pairing failed for another reason (message in [WebcamScanState.message]). The camera is closed.
  failed,
}

class WebcamScanState {
  final WebcamScanPhase phase;
  final String? message;

  /// True while the pictures hold no code and look out of focus: the dialog then
  /// says to move the phone a little closer or further away.
  final bool looksBlurry;
  const WebcamScanState(this.phase, [this.message, this.looksBlurry = false]);

  /// True while the camera is open and a live picture is worth showing.
  bool get cameraOn =>
      phase == WebcamScanPhase.scanning ||
      phase == WebcamScanPhase.notCardKeep ||
      phase == WebcamScanPhase.newerVersion;

  /// True when the dialog should offer to try again.
  bool get canRetry =>
      phase == WebcamScanPhase.busy ||
      phase == WebcamScanPhase.expired ||
      phase == WebcamScanPhase.failed ||
      phase == WebcamScanPhase.denied;
}

/// Turns an error from pairing into a message and whether the code was the problem.
typedef PairCode = Future<Object?> Function(String codeText);

/// Opens the webcam, takes a still three or four times a second, reads QR codes
/// out of them off the main thread, and pairs with the first good CardKeep code.
/// The camera is closed the moment a good code is read, and on [dispose].
class WebcamScanController extends ChangeNotifier {
  final WebcamSource source;
  final PairCode onCode;

  /// Reads a picture: the QR text if any and how sharp it is. The real one runs
  /// on a background isolate. Tests give a fake.
  final Future<FrameReading> Function(Uint8List bytes) read;

  /// The pause between stills.
  final Duration interval;

  /// How long the warning for a QR that is not a CardKeep code stays up after it was last seen.
  final Duration warningFor;

  /// How many pictures in a row without a code must look blurry before saying so.
  final int blurryFrames;

  /// A picture with no code whose sharpness is below this counts as blurry.
  final double blurryBelow;

  WebcamScanState _state = const WebcamScanState(WebcamScanPhase.starting);
  WebcamScanState get state => _state;

  bool _disposed = false;
  int _run = 0;
  int _blurRun = 0;
  DateTime? _flaggedAt;

  /// [decode] is the old way to read a QR only (no focus measure); [read] reads both.
  WebcamScanController({
    required this.source,
    required this.onCode,
    Future<String?> Function(Uint8List bytes)? decode,
    Future<FrameReading> Function(Uint8List bytes)? read,
    this.interval = const Duration(milliseconds: 280),
    this.warningFor = const Duration(seconds: 3),
    this.blurryFrames = 3,
    this.blurryBelow = FrameReader.blurryBelow,
  }) : read = read ?? (decode != null ? ((b) async => FrameReading(await decode(b), -1)) : FrameReader.readInIsolate);

  void _set(WebcamScanPhase phase, [String? message]) {
    if (_disposed) return;
    _state = WebcamScanState(phase, message, _state.looksBlurry && phase == WebcamScanPhase.scanning);
    notifyListeners();
  }

  void _setBlurry(bool blurry) {
    if (_disposed || _state.looksBlurry == blurry || _state.phase != WebcamScanPhase.scanning) return;
    _state = WebcamScanState(_state.phase, _state.message, blurry);
    notifyListeners();
  }

  /// Opens the camera and starts looking. Call again to try again.
  Future<void> start() async {
    final run = ++_run;
    _flaggedAt = null;
    _blurRun = 0;
    _set(WebcamScanPhase.starting);
    final opened = await source.open();
    if (_disposed || run != _run) {
      await source.close();
      return;
    }
    switch (opened) {
      case WebcamOpen.none:
        _set(WebcamScanPhase.noCamera);
        return;
      case WebcamOpen.denied:
        _set(WebcamScanPhase.denied);
        return;
      case WebcamOpen.busy:
        _set(WebcamScanPhase.busy, source.detail);
        return;
      case WebcamOpen.ready:
        break;
    }
    _set(WebcamScanPhase.scanning);
    unawaited(_loop(run));
  }

  Future<void> _loop(int run) async {
    while (!_disposed && run == _run && _state.cameraOn) {
      final started = DateTime.now();
      final frame = await source.captureFrame();
      if (_disposed || run != _run) return;
      if (frame != null) {
        final reading = await read(frame);
        if (_disposed || run != _run) return;
        final text = reading.text;
        if (text != null) {
          _blurRun = 0;
          _setBlurry(false);
          if (await _handle(text, run)) return;
        } else if (reading.sharpness >= 0) {
          // No code in view: is it that the picture is out of focus?
          _blurRun = reading.sharpness < blurryBelow ? _blurRun + 1 : 0;
          _setBlurry(_blurRun >= blurryFrames);
        }
      }
      // The warning for a wrong code fades after a few seconds without it.
      final flagged = _flaggedAt;
      if (flagged != null &&
          _state.phase != WebcamScanPhase.scanning &&
          DateTime.now().difference(flagged) > warningFor) {
        _flaggedAt = null;
        _set(WebcamScanPhase.scanning);
      }
      final wait = interval - DateTime.now().difference(started);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
  }

  /// A QR was read. True when the loop should stop (a good code, camera closed).
  Future<bool> _handle(String text, int run) async {
    try {
      PairingPayload.parse(text);
    } on SyncFormatException catch (e) {
      final newer = e.message.contains('newer');
      final phase = newer ? WebcamScanPhase.newerVersion : WebcamScanPhase.notCardKeep;
      if (_state.phase != phase) _set(phase, newer ? e.message : null);
      _flaggedAt = DateTime.now();
      return false;
    }
    // A good code: let go of the camera now, then pair.
    _run++;
    await source.close();
    if (_disposed) return true;
    _set(WebcamScanPhase.pairing);
    final error = await onCode(text);
    if (_disposed) return true;
    if (error == null) {
      _set(WebcamScanPhase.done);
    } else if (error is SyncException && error.code == 'bad_token') {
      _set(WebcamScanPhase.expired, error.message);
    } else {
      _set(WebcamScanPhase.failed, error is SyncException ? error.message : '$error');
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _run++;
    unawaited(source.close());
    super.dispose();
  }
}
