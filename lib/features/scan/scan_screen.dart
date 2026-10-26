import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/plural.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/storage/storage_errors.dart';
import '../../scan/card_detector.dart';
import '../../scan/finger_quad.dart';
import '../../scan/geometry.dart';
import '../../scan/live_detector_worker.dart';
import '../../scan/quad_smoother.dart';
import '../../scan/quality.dart';
import '../../scan/scan_pipeline.dart';
import '../../scan/scan_worker.dart';
import '../../scan/sweep_detector_worker.dart';
import '../../scan/sweep_tracker.dart';
import '../events/events_screens.dart';
import '../onboarding/coach.dart';
import 'scan_review.dart';
import 'sweep_painter.dart';

/// Scan screen (mockup Scan.dc.html): live outline, one hint at a time,
/// auto-capture when the card is clean and steady, manual shutter always.
class ScanScreen extends ConsumerStatefulWidget {
  /// 'batch' or 'pile' to start in that mode; [pick] opens the photo picker first.
  final String? mode;
  final bool pick;
  const ScanScreen({super.key, this.mode, this.pick = false});

  /// Set before opening the scanner to photograph the back of a card already
  /// in the review queue (after Batch or Pile); the scanner returns the card
  /// with both sides ([ScanHandoff]) when popped.
  static ScanHandoff? backRequest;
  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

enum _CamState { starting, ready, denied, deniedForever, noCamera, error }

class _ScanScreenState extends ConsumerState<ScanScreen>
    with WidgetsBindingObserver, RouteAware, SingleTickerProviderStateMixin {
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
  Size _frameSize = Size.zero; // portrait, detection space

  /// The outline the live preview draws: the detector's card, smoothed across
  /// frames and held for a moment when a frame misses it.
  final _smooth = QuadSmoother();
  SmoothedQuad? _shown;
  final _liveDetector = LiveDetectorWorker(); // one isolate for the whole session
  bool _exposureLocked = false;
  bool _exposureLowered = false; // exposure compensation down while a glossy card reflects
  double _minExposure = 0, _maxExposure = 0;
  bool _starting = false; // the permission dialog pauses/resumes the app mid-start
  bool _picking = false; // the photo picker pauses/resumes the app; keep the camera as is
  bool _covered = false; // another screen (review, queue, crop) is on top: camera off
  bool _flash = false; // white shutter flash on a Batch/Pile capture (phone test F40)
  final _auto = AutoCapture();

  // Sweep (S14c): cards tracked across preview frames, each captured once.
  final _sweep = SweepTracker();
  final _sweepDetector = SweepDetectorWorker(); // one isolate for the whole session
  bool _sweepCapturing = false;
  int _sweepMs = 0; // detector time per frame (long-press the counter to see it)
  bool _sweepDebug = false; // long-press the counter: speed, and why each card waits
  final _sweepStamps = <DateTime>[]; // frames analysed in the last second
  late final AnimationController _wipe = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  /// When set, the next capture is the back of this card.
  ScanHandoff? _awaitingBackOf;

  /// Opened from a card's review screen to add its back ([ScanScreen.backRequest]):
  /// the front and back go back to that screen instead of a new one.
  bool _returnBack = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mode = _Mode.values.where((m) => m.name == widget.mode).firstOrNull ?? _Mode.single;
    // Batch/Pile feedback once the background reader is done with a capture (F39, F40).
    ScanWorker.onAlreadyCaptured = () {
      if (mounted && !_covered) showMessage(context, 'Already captured: that card is in the review queue');
    };
    ScanWorker.onTaggedIds = (tag, ids) {
      if (tag is! int) return;
      _sweepIds[tag] = ids;
      final i = _sweepHashes.indexWhere((h) => h.trackId == tag);
      if (i >= 0) {
        if (ids.isEmpty) {
          _sweepHashes.removeAt(i); // nothing was queued: not a repeat of anything
        } else {
          _sweepHashes[i]
            ..ids = ids
            ..pending = false;
        }
      }
      // The track was a logo box that an enclosing card replaced: its entry is junk.
      if (_discardOnLand.remove(tag)) unawaited(_discardQueued(ids));
    };
    ScanWorker.onSweepRetry = (tag) {
      if (!mounted || tag is! int) return;
      _sweepHashes.removeWhere((h) => h.trackId == tag);
      _lastTry.add(tag);
      // Back to "found" soon: the card is still under the camera.
      setState(
        () => _sweep.markMissed(tag, DateTime.now().subtract(_sweep.retryAfter - const Duration(milliseconds: 400))),
      );
    };
    ScanWorker.onTagged = (tag, added, already, failed, empty) {
      if (!mounted || tag is! int) return;
      setState(() {
        if (added == 0 && already == 0 && empty > 0) {
          _sweep.markNotCard(tag, DateTime.now());
        } else if (added > 0) {
          _sweep.markDone(tag);
          HapticFeedback.mediumImpact();
        } else if (already > 0) {
          _sweep.markDone(tag, note: 'Already in queue');
        } else {
          _sweep.markMissed(tag, DateTime.now());
        }
      });
    };
    ScanWorker.onJobDone = (added, pile) {
      if (!mounted || _covered || !pile) return;
      showMessage(
        context,
        added == 0 ? 'No cards found in that photo' : 'Captured: ${plural(added, 'card', 'cards')} found',
      );
    };
    if (ScanScreen.backRequest case final front?) {
      ScanScreen.backRequest = null;
      _awaitingBackOf = front;
      _returnBack = true;
      _mode = _Mode.single;
    }
    if (widget.pick) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fromGallery();
      });
    } else {
      _start();
    }
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
    // A message from the camera (\
    final c = _cam;
    _cam = null;
    _live = null;
    _busy = false;
    c?.dispose();
  }

  @override
  void didPopNext() {
    _covered = false;
    // Back from an emptied queue ("Remove all"): a new sweep starts at 0 done,
    // not "7 of 7 done" from the last one (third sweep test).
    if (ref.read(queueProvider).value?.isEmpty ?? false) _resetSweep();
    if (mounted) _start();
  }

  void _resetSweep() {
    _sweep.reset();
    _sweepHashes.clear();
    _sweepIds.clear();
    _discardOnLand.clear();
    _lastTry.clear();
  }

  @override
  void dispose() {
    ScanWorker.onAlreadyCaptured = null;
    ScanWorker.onJobDone = null;
    ScanWorker.onTagged = null;
    ScanWorker.onTaggedIds = null;
    ScanWorker.onSweepRetry = null;
    _wipe.dispose();
    _sweepDetector.dispose();
    _liveDetector.dispose();
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
      try {
        _minExposure = await c.getMinExposureOffset();
        _maxExposure = await c.getMaxExposureOffset();
      } catch (_) {
        _minExposure = _maxExposure = 0; // no exposure compensation on this camera
      }
      _exposureLowered = false;
      // The torch stays as you left it, also after Retake (phone test F24).
      await c.setFlashMode(_torch ? FlashMode.torch : FlashMode.off).catchError((_) {});
      if (!mounted) {
        await c.dispose();
        return;
      }
      _cam = c;
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
    // Sweep analyses as often as the detector keeps up (it drops frames while busy).
    final gap = _mode == _Mode.sweep ? 60 : 180;
    if (_busy || _analysing || now.difference(_lastFrame).inMilliseconds < gap) return;
    _analysing = true;
    _lastFrame = now;
    final sweeping = _mode == _Mode.sweep;
    final frame = _portraitGray(img, cam.description.sensorOrientation, withSkin: !sweeping);
    if (sweeping) return _sweepFrame(frame, _copyYuv(img, cam.description.sensorOrientation));
    _liveDetector
        .detect(frame)
        .then((d) {
          if (!mounted || _busy) return;
          final now = DateTime.now();
          _frameSize = Size(frame.width.toDouble(), frame.height.toDouble());
          // The outline is smoothed across frames and held for ~600 ms when a
          // frame misses the card; steadiness is judged on the smoothed outline.
          final sm = _smooth.update(d.card, now: now, frameWidth: frame.width.toDouble());
          _shown = sm;
          _manageExposure(d, sm);
          // A held frame keeps the last real reading, so the hint and the
          // capture timer don't flicker with a missed detection.
          if (sm == null || !sm.held) _live = d;
          setState(() {});
          if (sm == null) _waitForClear = false;
          if (_mode != _Mode.pile && !_waitForClear) {
            if (sm == null) {
              _auto.update(issues: d.issues, steady: false, now: now); // the card is gone: start over
            } else if (!sm.held && _auto.update(issues: d.issues, steady: sm.steady, now: now)) {
              HapticFeedback.mediumImpact();
              _capture();
            }
          }
        })
        .catchError((Object _) {})
        .whenComplete(() => _analysing = false);
  }

  /// Exposure follows the card: locked once found (so the shot is as bright as
  /// the preview), but not while a glossy card is clipping white. Then it is
  /// auto, with compensation down by one stop, which brings the text back.
  void _manageExposure(Detection d, SmoothedQuad? sm) {
    final cam = _cam;
    if (cam == null) return;
    final canLower = _maxExposure - _minExposure > 0.01;
    final glossy = d.card != null && d.metrics.specular >= 0.04;
    final calm = d.card == null || d.metrics.specular < 0.01;
    if (canLower && glossy && !_exposureLowered) {
      _exposureLowered = true;
      cam.setExposureOffset((-1.0).clamp(_minExposure, _maxExposure)).catchError((_) => 0.0);
    } else if (canLower && calm && _exposureLowered) {
      _exposureLowered = false;
      cam.setExposureOffset(0).catchError((_) => 0.0);
    }
    if (sm != null && !_exposureLocked && !_exposureLowered) {
      _exposureLocked = true;
      cam.setExposureMode(ExposureMode.locked).catchError((_) {});
    } else if ((sm == null || _exposureLowered) && _exposureLocked) {
      _exposureLocked = false;
      cam.setExposureMode(ExposureMode.auto).catchError((_) {});
    }
  }

  // --------------------------------------------------------------- sweep

  void _sweepFrame(GrayFrame frame, YuvFrame yuv) {
    _sweepDetector
        .detect(frame)
        .then((f) {
          if (!mounted || _mode != _Mode.sweep) return;
          final now = DateTime.now();
          _sweepMs = f.ms;
          _sweepStamps
            ..add(now)
            ..removeWhere((t) => now.difference(t).inMilliseconds > 1000);
          if (kDebugMode) debugPrint('sweep: ${f.ms} ms, ${f.cards.length} cards, ${_sweepStamps.length}/s');
          final w = f.width.toDouble(), h = f.height.toDouble();
          _frameSize = Size(w, h);
          _sweep.update(f.cards, f.sharpness, width: w, height: h, now: now);
          for (final (oldId, newId) in _sweep.takeSuperseded()) {
            unawaited(_replaceJunk(oldId, newId));
          }
          // The wipe controller doubles as the overlay's clock: outlines glide and
          // fade between analysed frames, so it runs for the whole sweep.
          if (!_wipe.isAnimating) _wipe.repeat();
          setState(() {});
          // A capture in flight never blocks tracking; the next steady card waits for it.
          // Run every frame so each card's reason is current; only capture when free.
          final next = _sweep.next(width: w, height: h, now: now, busy: _sweepCapturing);
          if (next != null && !_sweepCapturing) _sweepCapture(next, f.width, f.height, yuv);
        })
        .catchError((Object _) {})
        .whenComplete(() => _analysing = false);
  }

  /// Hands the tracked card to the background reader without stopping the
  /// preview: a full-resolution still, one at a time, cut loosely around the
  /// card ([cropStillForSweep]).
  /// Picture hashes of every card sent for reading this sweep ([dHash]), with the
  /// queue rows they made: a repeat only counts while one of those rows is still there.
  final _sweepHashes = <_SweepHash>[];

  /// Queue rows each Sweep track made.
  final _sweepIds = <int, List<String>>{};

  /// Tracks that were a logo box inside a card and were replaced before their
  /// result landed: whatever they queue is junk and goes.
  final _discardOnLand = <int>{};

  /// Tracks on their second, final try after a garbled first reading.
  final _lastTry = <int>{};

  Future<void> _discardQueued(List<String> ids) async {
    final queue = await ref.read(cardQueueProvider.future);
    for (final id in ids) {
      await queue.discard(id);
    }
  }

  /// An enclosing card appeared around [oldId]'s outline (a logo box, band or
  /// illustration): the entry made from the box is junk, the card is read afresh.
  Future<void> _replaceJunk(int oldId, int newId) async {
    _sweepHashes.removeWhere((h) => h.trackId == oldId);
    _lastTry.remove(oldId);
    final ids = _sweepIds.remove(oldId);
    if (ids != null) {
      sweepLog('replacing junk entry of track $oldId (card $newId encloses it)');
      await _discardQueued(ids);
    } else {
      _discardOnLand.add(oldId);
    }
  }

  Future<void> _sweepCapture(SweepTrack track, int frameW, int frameH, YuvFrame yuv) async {
    final c = _cam;
    final worker = ref.read(scanWorkerProvider.notifier);
    if (c == null || worker.full) return;
    _sweepCapturing = true;
    setState(() => _sweep.markReading(track.id));
    final quad = track.quad;
    // Every other card in view is painted over in the crop, so its text can't
    // leak into this one.
    final others = [
      for (final t in _sweep.tracks)
        if (t.id != track.id && t.seen == track.seen) t.quad,
    ];
    try {
      // Always a full-resolution still: preview cut-outs were too soft for
      // small print (third sweep test). Taken while the preview keeps running;
      // a blurry one is retaken up to twice, a quarter second apart (fifth test).
      SweepStillCrop? cut;
      for (var attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) await Future<void>.delayed(const Duration(milliseconds: 250));
        final shot = await c.takePicture();
        if (attempt == 0) unawaited(HapticFeedback.selectionClick());
        if (_torch) await c.setFlashMode(FlashMode.torch).catchError((_) {});
        final c2 = await compute(cropStillForSweep, (await _takeBytes(shot), quad, others, frameW, frameH));
        cut = c2;
        if (c2.sharpness >= _sweep.minSharpness) break;
        sweepLog('track ${track.id} still ${attempt + 1} blurry (${c2.sharpness.toStringAsFixed(1)}), retaking');
      }
      if (!cut!.ok) {
        // Mostly flat table colour: nothing to read. Try again later.
        if (mounted) setState(() => _sweep.markMissed(track.id, DateTime.now()));
        return;
      }
      final crop = cut.jpeg;
      // The same card cut twice this session (it left the view and came back):
      // its picture matches one already sent, so it isn't read again.
      final hash = await compute(dHash, crop);
      // A repeat only when the picture is nearly the same (4 of 64 bits) AND a
      // queue or saved row from that capture still exists. Two dark blue cards
      // collided at 10 bits and Millennium was "Already in queue" with no row.
      final twin = _sweepHashes.where((h) => hammingDistance(h.hash, hash) <= 4).firstOrNull;
      if (twin != null) {
        if (twin.pending) {
          // Still being read: look again in a moment, once it has a row (or not).
          sweepLog('track ${track.id} looks like card ${twin.trackId} still being read, waiting');
          if (mounted) setState(() => _sweep.markMissed(track.id, DateTime.now()));
          return;
        }
        final queue = await ref.read(cardQueueProvider.future);
        if (await queue.anyLive(twin.ids)) {
          sweepLog('track ${track.id} repeats card ${twin.trackId} (picture, rows ${twin.ids.length})');
          if (mounted) setState(() => _sweep.markDone(track.id, note: 'Already in queue'));
          return;
        }
        _sweepHashes.remove(twin); // its rows are gone: this is a new capture
      }
      _sweepHashes.add(_SweepHash(hash, track.id));
      await worker.add(
        ScanJob(crop, tag: track.id, fallback: cut.fallback, source: cut.source, lastTry: _lastTry.remove(track.id)),
      );
    } catch (_) {
      if (mounted) setState(() => _sweep.markMissed(track.id, DateTime.now()));
    } finally {
      _sweepCapturing = false;
    }
  }

  /// Copies the preview frame's colour planes out of the camera buffer, which
  /// is reused once this callback returns.
  static YuvFrame _copyYuv(CameraImage img, int sensorOrientation) {
    final p = img.planes;
    return YuvFrame(
      Uint8List.fromList(p[0].bytes),
      Uint8List.fromList(p[1].bytes),
      Uint8List.fromList(p[2].bytes),
      width: img.width,
      height: img.height,
      yRowStride: p[0].bytesPerRow,
      uvRowStride: p[1].bytesPerRow,
      uvPixelStride: p[1].bytesPerPixel ?? 1,
      sensorOrientation: sensorOrientation,
    );
  }

  /// Y plane -> portrait greyscale, subsampled to ~640 px on the long edge.
  static GrayFrame _portraitGray(CameraImage img, int sensorOrientation, {bool withSkin = false}) {
    final y = img.planes.first;
    final w = img.width, h = img.height, stride = y.bytesPerRow;
    final step = (w > h ? w : h) ~/ 640 + 1;
    final ow = h ~/ step, oh = w ~/ step; // rotated to portrait
    final out = Uint8List(ow * oh);
    final src = y.bytes;
    // Colour planes, for the skin mask that lets a finger on the card's edge be
    // ignored: Cb is the U plane, Cr the V plane, both half size.
    final colour = withSkin && img.planes.length >= 3;
    final skin = colour ? Uint8List(ow * oh) : null;
    final ub = colour ? img.planes[1].bytes : null, vb = colour ? img.planes[2].bytes : null;
    final uStride = colour ? img.planes[1].bytesPerRow : 0, uPx = colour ? (img.planes[1].bytesPerPixel ?? 1) : 1;
    final vStride = colour ? img.planes[2].bytesPerRow : 0, vPx = colour ? (img.planes[2].bytesPerPixel ?? 1) : 1;
    var i = 0;
    final cw = sensorOrientation == 270;
    for (var v = 0; v < oh; v++) {
      for (var u = 0; u < ow; u++) {
        final sx = cw ? (w - 1 - v * step) : v * step;
        final sy = cw ? u * step : (h - 1 - u * step);
        final lum = src[sy * stride + sx];
        out[i] = lum;
        if (skin != null && lum >= skinYMin && lum <= skinYMax) {
          final cb = ub![(sy >> 1) * uStride + (sx >> 1) * uPx], cr = vb![(sy >> 1) * vStride + (sx >> 1) * vPx];
          if (isSkinYCrCb(lum, cb, cr)) skin[i] = 255;
        }
        i++;
      }
    }
    return GrayFrame(out, ow, oh, skin: skin);
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
        // Shutter flash and a clear buzz, so a capture never goes unnoticed (F40).
        setState(() => _flash = true);
        unawaited(HapticFeedback.mediumImpact());
        Future.delayed(const Duration(milliseconds: 140), () {
          if (mounted) setState(() => _flash = false);
        });
        await worker.add(ScanJob(await _takeBytes(shot), pile: _mode == _Mode.pile));
        if (mounted && _mode == _Mode.pile) showMessage(context, 'Captured: reading the cards…');
        _waitForClear = true; // don't re-shoot the same card
        if (_torch) await c.setFlashMode(FlashMode.torch).catchError((_) {});
      } on CameraException catch (e) {
        if (mounted) showMessage(context, 'Capture failed: ${e.description ?? e.code}');
      } catch (e) {
        if (mounted) showMessage(context, isStorageFull(e) ? storageFullHelp : 'Could not save that photo. Try again.');
      } finally {
        _auto.reset();
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    setState(() => _busy = true);
    try {
      // The live outline (smoothed, finger-completed) stands in when the edge
      // search on the photo can't see the card's whole border.
      final liveQuad = _smooth.shown, liveFrame = _frameSize;
      final glossy = (_live?.metrics.specular ?? 0) >= Gates.burstSpecular;
      if (c.value.isStreamingImages) await c.stopImageStream();
      Uint8List bytes;
      if (glossy) {
        // A reflection that hides text in one photo is usually gone in the
        // next: take three quickly and read the one with the least glare.
        final shots = <Uint8List>[];
        for (var n = 0; n < 3; n++) {
          if (n > 0) await Future.delayed(const Duration(milliseconds: 150));
          shots.add(await _takeBytes(await c.takePicture()));
        }
        bytes = shots[await compute(pickBestStill, shots)];
      } else {
        bytes = await _takeBytes(await c.takePicture());
      }
      await _readOne(
        bytes,
        liveQuad: liveQuad,
        liveFrame: liveFrame == Size.zero ? null : (width: liveFrame.width.round(), height: liveFrame.height.round()),
      );
    } on CameraException catch (e) {
      if (mounted) showMessage(context, 'Capture failed: ${e.description ?? e.code}');
    } catch (e, st) {
      // Never loop silently: the photo is kept in the queue, say what failed.
      debugPrint('Card read failed: $e\n$st');
      if (mounted) {
        showMessage(
          context,
          isStorageFull(e)
              ? storageFullHelp
              : 'Could not read that card. Try again, or pick the photo from the gallery.',
        );
      }
    } finally {
      await _resume();
    }
  }

  Future<void> _resume() async {
    _auto.reset();
    _smooth.reset();
    _shown = null;
    _live = null;
    if (!mounted || _covered) return;
    setState(() => _busy = false);
    final c = _cam;
    if (c != null && c.value.isInitialized && !c.value.isStreamingImages) {
      try {
        // Taking a picture can switch the torch off; put it back.
        if (_torch) await c.setFlashMode(FlashMode.torch).catchError((_) {});
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
          await worker.add(ScanJob(await f.readAsBytes(), pile: _mode == _Mode.pile || files.length == 1));
        }
        if (mounted) unawaited(context.push('/queue'));
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, isStorageFull(e) ? storageFullHelp : 'Could not read that photo. Try another one.');
      }
    } finally {
      _busy = false;
      if (mounted && !_covered) await _start();
    }
  }

  /// One card, read right away: stored in the queue first (so it's never
  /// lost), then reviewed.
  Future<void> _readOne(Uint8List jpeg, {Quad? liveQuad, ({int width, int height})? liveFrame}) async {
    final pipeline = await ref.read(scanPipelineProvider.future);
    final queue = await ref.read(cardQueueProvider.future);
    // The capture stays in pending/ until its card is in the queue (MOB-REL-0002).
    final (sides, pending) = await pipeline.processKeeping(jpeg, fallback: liveQuad, fallbackFrame: liveFrame);
    final store = await ref.read(imageStoreProvider.future);
    if (sides.isEmpty) return store.donePending(pending);
    if (!mounted) return; // kept: recovered and queued on the next start
    final back = _awaitingBackOf;
    if (back != null) {
      setState(() => _awaitingBackOf = null);
      await queue.setBack(back.cardId, back.front, sides.first);
      await store.donePending(pending);
      final both = ScanHandoff(cardId: back.cardId, front: back.front, back: sides.first);
      if (mounted && _returnBack) return context.pop(both); // back to the review it came from
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
    // One card is always a deliberate scan, so no "already captured" check here:
    // only Batch and Pile skip repeats (F39). Saving still flags a duplicate.
    final id = await queue.enqueue(sides.first);
    await store.donePending(pending);
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
    final ready = _state == _CamState.ready && _cam != null;
    return CoachScope(
      tipId: 'sweep',
      enabled: ready && _mode == _Mode.sweep,
      steps: const [
        CoachStep(
          'scan.modes',
          'Sweep',
          'Lay cards on a dark table with a little gap between them, then move the phone slowly over them. Each card is outlined, read once and turns green.',
        ),
        CoachStep(
          'scan.finish',
          'Finish',
          'Tap Finish when you are done. Clear cards go to Contacts; the rest wait in the Review queue.',
        ),
        CoachStep('scan.torch', 'Light', 'The torch helps in a dim room.'),
      ],
      child: CoachScope(
        tipId: 'scan',
        enabled: ready && _mode != _Mode.sweep,
        steps: const [
          CoachStep(
            'scan.modes',
            'Four ways to scan',
            'One card for a single card. Batch for one after another. Pile for several in one photo. Sweep to move over a whole table of cards.',
          ),
          CoachStep('scan.torch', 'Torch', 'Switch the light on for a dim room.'),
          CoachStep(
            'scan.gallery',
            'Pick photos',
            'Read cards from pictures already in your gallery. No camera needed.',
          ),
          CoachStep(
            'scan.shutter',
            'Take the photo',
            'Hold steady over a card and it is taken for you. Tap the round button to take it yourself.',
          ),
        ],
        child: AnnotatedRegion<SystemUiOverlayStyle>(
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
              _CamState.noCamera => _blocked(
                'No camera found',
                'You can still pick card photos from your gallery.',
                null,
              ),
              _CamState.error => _blocked(
                'The camera could not start',
                _error ?? '',
                FilledButton(onPressed: _start, child: const Text('Try again')),
              ),
            },
          ),
        ),
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
            _Mode.sweep => 'Move slowly over the cards',
            _Mode.batch when _waitForClear => 'Got it. Next card',
            _ => 'Hold steady…',
          }
        : issues.first.hint;
    final sweeping = _mode == _Mode.sweep;
    final sweepHint = _sweep.tracks.isEmpty
        ? 'Lay the cards out and move slowly over them'
        : _sweep.tracks.any((t) => t.state == SweepState.found)
        ? 'Hold over a card for a moment'
        : 'Move on to the next cards';
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
                  if (sweeping)
                    AnimatedBuilder(
                      animation: _wipe,
                      builder: (_, _) {
                        // Outlines glide with the view between analysed frames and fade once a card leaves it.
                        final now = DateTime.now();
                        return CustomPaint(
                          painter: SweepPainter(
                            [
                              for (final t in _sweep.tracks)
                                (
                                  _sweep.displayQuad(t, now),
                                  t.state,
                                  _sweepDebug && t.state == SweepState.found ? t.wait ?? 'ready' : t.note,
                                ),
                            ],
                            _frameSize,
                            _wipe.value,
                            opacities: [for (final t in _sweep.tracks) _sweep.opacity(t, now)],
                          ),
                        );
                      },
                    )
                  else
                    CustomPaint(painter: _OutlinePainter(_live, _shown, _frameSize, _mode == _Mode.pile)),
                ],
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _flash ? 0.85 : 0,
            duration: const Duration(milliseconds: 120),
            child: const ColoredBox(color: Colors.white),
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
                  CoachTarget(
                    id: 'scan.modes',
                    child: _ModeSwitch(
                      mode: _mode,
                      onChanged: _awaitingBackOf != null
                          ? null
                          : (m) => setState(() {
                              _mode = m;
                              _resetSweep();
                              _wipe.stop();
                            }),
                    ),
                  ),
                  const Spacer(),
                  CoachTarget(
                    id: 'scan.torch',
                    child: _RoundIcon(
                      icon: _torch ? Icons.flash_on : Icons.flash_off,
                      label: _torch ? 'Torch off' : 'Torch on',
                      onTap: () async {
                        _torch = !_torch;
                        await c.setFlashMode(_torch ? FlashMode.torch : FlashMode.off).catchError((_) {});
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Event the cards go to (scan session), under the top bar.
        const Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            child: Padding(padding: EdgeInsets.only(top: 76), child: ActiveEventChip()),
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
                  if (sweeping && _sweep.total > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      // Long-press: how fast the detector is running on this phone.
                      child: GestureDetector(
                        onLongPress: () {
                          setState(() => _sweepDebug = !_sweepDebug);
                          showMessage(
                            context,
                            _sweepDebug
                                ? '${_sweepStamps.length} frames a second, $_sweepMs ms each. Cards show why they wait.'
                                : 'Debug labels off',
                          );
                        },
                        child: Pill(
                          '${_sweep.doneCount} of ${_sweep.total} done',
                          bg: const Color(0xFF2E9E5B),
                          fg: Colors.white,
                        ),
                      ),
                    ),
                  if (_awaitingBackOf != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Pill('BACK SIDE', bg: Tokens.action, fg: Tokens.onAction),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(99)),
                    child: Text(
                      sweeping ? sweepHint : (_busy ? 'Reading card…' : hint),
                      style: AppText.bodyStrong.copyWith(color: Colors.white),
                      semanticsLabel: 'Hint: ${sweeping ? sweepHint : (_busy ? 'Reading card' : hint)}',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      CoachTarget(
                        id: 'scan.gallery',
                        child: _RoundIcon(
                          icon: Icons.photo_library_outlined,
                          label: 'Pick photos',
                          onTap: _busy ? null : _fromGallery,
                        ),
                      ),
                      if (sweeping)
                        CoachTarget(
                          id: 'scan.finish',
                          child: SizedBox(
                            height: 78,
                            child: Center(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Tokens.brandOrange,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(140, 52),
                                ),
                                onPressed: () => context.push('/queue'),
                                icon: const Icon(Icons.check),
                                label: const Text('Finish'),
                              ),
                            ),
                          ),
                        )
                      else
                        CoachTarget(
                          id: 'scan.shutter',
                          child: _Shutter(busy: _busy && _mode == _Mode.single, onTap: _capture),
                        ),
                      _awaitingBackOf != null
                          ? _RoundIcon(
                              icon: Icons.skip_next,
                              label: 'Skip back side',
                              onTap: () async {
                                final f = _awaitingBackOf!;
                                setState(() => _awaitingBackOf = null);
                                if (_returnBack) return context.pop();
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
  final SmoothedQuad? shown;
  final Size frame;
  final bool pile;
  _OutlinePainter(this.d, this.shown, this.frame, this.pile);

  @override
  void paint(Canvas canvas, Size size) {
    final det = d;
    if (det == null || frame == Size.zero) return;
    final sx = size.width / frame.width, sy = size.height / frame.height;
    // One card and Batch draw the smoothed outline (fading while it is only
    // being held); Pile draws every card as detected.
    final quads = pile ? det.cards : [?shown?.quad];
    final fade = pile ? 1.0 : (shown?.opacity ?? 1.0);
    for (final q in quads) {
      final path = Path()..moveTo(q.tl.x * sx, q.tl.y * sy);
      for (final p in [q.tr, q.br, q.bl]) {
        path.lineTo(p.x * sx, p.y * sy);
      }
      path.close();
      final ok = det.clean || pile;
      canvas.drawPath(path, Paint()..color = (ok ? Tokens.brandOrange : Colors.white).withValues(alpha: 0.18 * fade));
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = (ok ? Tokens.brandOrange : Colors.white).withValues(alpha: fade),
      );
    }
  }

  @override
  bool shouldRepaint(_OutlinePainter old) => old.d != d || old.shown != shown || old.pile != pile;
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

enum _Mode { single, batch, pile, sweep }

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
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged!(value),
        // The transparent margin makes the touch target 48 dp tall (audit MOB-A11Y-0002).
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 7),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          decoration: BoxDecoration(
            color: mode == value ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(99),
          ),
          child: ExcludeSemantics(
            child: Text(
              label,
              style: AppText.label.copyWith(color: mode == value ? Colors.black : Colors.white, fontSize: 12.5),
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
        children: [
          seg('One card', _Mode.single),
          seg('Batch', _Mode.batch),
          seg('Pile', _Mode.pile),
          seg('Sweep', _Mode.sweep),
        ],
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

/// Reads a camera capture and deletes the camera's own copy in the cache:
/// from here on the only copy is pending/ (audit MOB-SEC-0003).
Future<Uint8List> _takeBytes(XFile shot) async {
  final bytes = await shot.readAsBytes();
  try {
    await File(shot.path).delete();
  } catch (_) {}
  return bytes;
}

/// A card's picture hash with the queue rows it made, for the repeat check.
class _SweepHash {
  final int hash;
  final int trackId;
  List<String> ids = const [];
  bool pending = true; // still being read: no rows yet
  _SweepHash(this.hash, this.trackId);
}
