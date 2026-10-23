import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'card_detector.dart';

/// One isolate that stays up for the whole Sweep session and runs
/// [sweepDetect] on each frame (S14c). compute() spawned a new isolate per
/// frame, which on a phone cost more than the detection itself; frames now
/// travel as transferable bytes, so nothing is copied between isolates.
class SweepDetectorWorker {
  Isolate? _isolate;
  SendPort? _send;
  ReceivePort? _receive;
  Completer<void>? _ready;
  final _pending = <int, Completer<SweepFrame>>{};
  int _nextId = 0;

  Future<void> start() {
    if (_ready != null) return _ready!.future;
    final ready = _ready = Completer<void>();
    final rp = _receive = ReceivePort();
    rp.listen((msg) {
      if (msg is SendPort) {
        _send = msg;
        ready.complete();
      } else if (msg is (int, SweepFrame?, String?)) {
        final (id, frame, error) = msg;
        final c = _pending.remove(id);
        if (c == null) return;
        frame != null ? c.complete(frame) : c.completeError(StateError(error ?? 'detection failed'));
      }
    });
    Isolate.spawn(_main, rp.sendPort, debugName: 'sweep-detector').then(
      (i) => _isolate = i,
      onError: (Object e) {
        if (!ready.isCompleted) ready.completeError(e);
      },
    );
    return ready.future;
  }

  /// Detects cards in [f]. The bytes are handed over, so [f] must not be used afterwards.
  Future<SweepFrame> detect(GrayFrame f) async {
    await start();
    final id = _nextId++;
    final c = _pending[id] = Completer<SweepFrame>();
    _send!.send((id, TransferableTypedData.fromList([f.bytes]), f.width, f.height));
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
      final (id, data, w, h) = msg as (int, TransferableTypedData, int, int);
      try {
        final bytes = data.materialize().asUint8List();
        reply.send((id, sweepDetect(GrayFrame(Uint8List.view(bytes.buffer), w, h)), null));
      } catch (e) {
        reply.send((id, null, '$e'));
      }
    });
  }
}
