import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'card_detector.dart';
import 'card_detector.dart' as cd show detect;

/// One isolate that stays up while the scanner is open and runs [detect] on
/// each preview frame (One card, Batch, Pile). compute() started a new isolate
/// for every frame, which cost more than the detection and capped the outline
/// at a few updates a second; this is the same idea as [SweepDetectorWorker].
class LiveDetectorWorker {
  Isolate? _isolate;
  SendPort? _send;
  ReceivePort? _receive;
  Completer<void>? _ready;
  final _pending = <int, Completer<Detection>>{};
  int _nextId = 0;

  Future<void> start() {
    if (_ready != null) return _ready!.future;
    final ready = _ready = Completer<void>();
    final rp = _receive = ReceivePort();
    rp.listen((msg) {
      if (msg is SendPort) {
        _send = msg;
        ready.complete();
      } else if (msg is (int, Detection?, String?)) {
        final (id, detection, error) = msg;
        final c = _pending.remove(id);
        if (c == null) return;
        detection != null ? c.complete(detection) : c.completeError(StateError(error ?? 'detection failed'));
      }
    });
    Isolate.spawn(_main, rp.sendPort, debugName: 'live-detector').then(
      (i) => _isolate = i,
      onError: (Object e) {
        if (!ready.isCompleted) ready.completeError(e);
      },
    );
    return ready.future;
  }

  /// Detects the card in [f]. The bytes are handed over, so [f] must not be used afterwards.
  Future<Detection> detect(GrayFrame f) async {
    await start();
    final id = _nextId++;
    final c = _pending[id] = Completer<Detection>();
    final skin = f.skin;
    _send!.send((
      id,
      TransferableTypedData.fromList([f.bytes]),
      f.width,
      f.height,
      skin == null ? null : TransferableTypedData.fromList([skin]),
    ));
    return c.future;
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _receive?.close();
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('detector stopped'));
    }
    _pending.clear();
    _isolate = null;
    _send = null;
    _receive = null;
    _ready = null;
  }

  static void _main(SendPort reply) {
    final inbox = ReceivePort();
    reply.send(inbox.sendPort);
    inbox.listen((msg) {
      final (id, data, w, h, skin) = msg as (int, TransferableTypedData, int, int, TransferableTypedData?);
      try {
        final bytes = Uint8List.view(data.materialize().asUint8List().buffer);
        final skinBytes = skin == null ? null : Uint8List.view(skin.materialize().asUint8List().buffer);
        reply.send((id, cd.detect(GrayFrame(bytes, w, h, skin: skinBytes)), null));
      } catch (e) {
        reply.send((id, null, '$e'));
      }
    });
  }
}
