import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/qr/qr_decoder.dart';
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
  const WebcamScanState(this.phase, [this.message]);

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

  /// Reads a QR out of picture bytes. The real one runs on a background isolate.
  final Future<String?> Function(Uint8List bytes) decode;

  /// The pause between stills.
  final Duration interval;

  /// How long the warning for a QR that is not a CardKeep code stays up after it was last seen.
  final Duration warningFor;

  WebcamScanState _state = const WebcamScanState(WebcamScanPhase.starting);
  WebcamScanState get state => _state;

  bool _disposed = false;
  int _run = 0;
  DateTime? _flaggedAt;

  WebcamScanController({
    required this.source,
    required this.onCode,
    Future<String?> Function(Uint8List bytes)? decode,
    this.interval = const Duration(milliseconds: 280),
    this.warningFor = const Duration(seconds: 3),
  }) : decode = decode ?? QrDecoder.decodeBytesInIsolate;

  void _set(WebcamScanPhase phase, [String? message]) {
    if (_disposed) return;
    _state = WebcamScanState(phase, message);
    notifyListeners();
  }

  /// Opens the camera and starts looking. Call again to try again.
  Future<void> start() async {
    final run = ++_run;
    _flaggedAt = null;
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
        final text = await decode(frame);
        if (_disposed || run != _run) return;
        if (text != null && await _handle(text, run)) return;
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
