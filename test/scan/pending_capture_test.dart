import 'dart:io';
import 'dart:typed_data';

import 'package:card_organizer/core/images/image_store.dart';
import 'package:card_organizer/scan/scan_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A plain photo: white card on a grey table.
Uint8List photo() {
  final i = img.Image(width: 1600, height: 1200)..clear(img.ColorRgb8(90, 90, 90));
  img.fillRect(i, x1: 250, y1: 300, x2: 1350, y2: 930, color: img.ColorRgb8(245, 245, 240));
  return Uint8List.fromList(img.encodeJpg(i));
}

void main() {
  late Directory dir;
  late ImageStore store;
  late ScanPipeline pipeline;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ck_pending');
    store = ImageStore(dir);
    pipeline = ScanPipeline(store: store, ocr: null, region: 'US');
  });
  tearDown(() => dir.delete(recursive: true));

  test('processKeeping leaves the capture in pending/ until the card is queued (MOB-REL-0002)', () async {
    final (sides, pending) = await pipeline.processKeeping(photo());
    expect(sides, isNotEmpty);
    expect(pending.existsSync(), isTrue, reason: 'a kill now must not lose the card');
    expect(store.orphanedPending().map((f) => f.path), [pending.path], reason: 'recovery finds it at the next start');
    await store.donePending(pending);
    expect(store.orphanedPending(), isEmpty);
  });

  test('process (no queue step afterwards) still cleans up', () async {
    await pipeline.process(photo());
    expect(store.orphanedPending(), isEmpty);
  });
}
