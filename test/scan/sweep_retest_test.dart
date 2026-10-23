// Cases from the second Sweep test on the S25 Ultra (0.7.2): repeats with
// different readings, upside-down crops, labels after numbers, Remove all.
import 'dart:io';
import 'dart:typed_data';

import 'package:card_organizer/core/cards/card_queue_repository.dart';
import 'package:card_organizer/core/db/database.dart';
import 'package:card_organizer/core/images/image_store.dart';
import 'package:card_organizer/parser/ocr.dart';
import 'package:card_organizer/parser/rules.dart';
import 'package:card_organizer/scan/card_detector.dart';
import 'package:card_organizer/scan/geometry.dart';
import 'package:card_organizer/scan/scan_pipeline.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

ScannedSide side(String hash, List<String> lines) =>
    ScannedSide(hash: hash, thumb: Uint8List(0), issues: const [], ocr: OcrPage.fromText(lines));

void main() {
  group('the same card read two ways is one card', () {
    test('a shared phone or email is enough, whatever the name reads as', () {
      final a = side('a', ['Bridgette Kipling', 'HR Manager', 'Enpress LLC', 'bkipling@enpress.com']);
      final b = side('b', ['Hr Manage', 'Bridgette Kipl Enpress LLC', 'bkipling@enpress.com']);
      expect(CardQueueRepository.sameCard(a, b), isTrue);
      final c = side('c', ['Rosa Delgado', 'Store Manager', 'Greenfield Garden Center', 'C 440 555 0185']);
      final d = side('d', ['Rosa Delga', 'Greenfield Garden', '440.555.0185']);
      expect(CardQueueRepository.sameCard(c, d), isTrue);
    });

    test('a close name at a close company matches; a different person does not', () {
      final a = side('a', ['Fritz Hoffmann', 'Program Manager', 'Lunar Corporation']);
      final b = side('b', ['Fritz Hofmann', 'Program Manager', 'Lunar Corp']);
      expect(CardQueueRepository.sameCard(a, b), isTrue);
      final c = side('c', ['Justin Fink', 'Sales', 'Enpress LLC', 'jfink@enpress.com']);
      final d = side('d', ['Robert Pristas', 'Engineer', 'Enpress LLC', 'bpristas@enpress.com']);
      expect(CardQueueRepository.sameCard(c, d), isFalse);
    });

    test('the queue check uses it', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final dir = await Directory.systemTemp.createTemp('ck_sweep2');
      addTearDown(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
      final q = CardQueueRepository(db, ImageStore(dir));
      await q.enqueue(side('a', ['Rosa Delgado', 'Greenfield Garden Center', 'rosa@greenfield.example']));
      expect(await q.recentlyCaptured(side('b', ['Rosa Delga', 'rosa@greenfield.example'])), isTrue);
      expect(await q.recentlyCaptured(side('c', ['Lena Hartmann', 'lena@cobalt.example'])), isFalse);
    });
  });

  group('Remove all', () {
    test('takes every waiting card out, and one undo puts them all back', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final dir = await Directory.systemTemp.createTemp('ck_sweep2');
      addTearDown(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
      final q = CardQueueRepository(db, ImageStore(dir));
      for (final n in ['Ann Lee', 'Bo Chen', 'Cy Diaz']) {
        await q.enqueue(side(n, [n, '${n.split(' ').first.toLowerCase()}@x.example']));
      }
      expect((await q.watchQueue().first).length, 3);
      final ids = await q.discardAll();
      expect(ids.length, 3);
      expect(await q.watchQueue().first, isEmpty);
      await q.restoreAll(ids);
      expect((await q.watchQueue().first).length, 3);
    });
  });

  group('which way up', () {
    test('contact details count: an upside-down reading finds none', () {
      final upright = OcrPage.fromText(['Bryan Miller', 'Enpress LLC', 'bmiller@enpress.com', '440 555 0101']);
      final upsideDown = OcrPage.fromText(['10l0 999 0bb', 'woc.ssaudua@ɹallimq', 'ƆꞀꞀ ssaɹdua', 'ɹallin uɐʎɹq']);
      expect(fieldBonus(upright), greaterThan(0.8));
      expect(fieldBonus(upsideDown), 0);
      expect(orientationScore(upright), greaterThan(orientationScore(upsideDown)));
    });

    test('the turn that finds the details wins', () {
      final as0 = orientationScore(OcrPage.fromText(['ɹallin uɐʎɹq', 'woc.ssaudua@ɹallimq']));
      final as180 = orientationScore(OcrPage.fromText(['Bryan Miller', 'bmiller@enpress.com', '440 555 0101']));
      expect(bestRotation({0: as0, 90: 0.1, 180: as180, 270: 0.1}), 180);
    });
  });

  group('phone labels after the number', () {
    test('office, cell, fax and direct after a number set its type', () {
      final c = parseCard(
        OcrPage.fromText([
          'Ryan Kirkwood',
          'Application Specialist',
          '216.432.5822 office',
          '216.559.5788 cell',
          '216.432.5888 fax',
          '216.432.5890 direct',
          'rk@horsburgh-scott.com',
        ]),
      );
      expect([for (final p in c.phones) p.label], ['office', 'mobile', 'office']);
      expect(c.faxes.length, 1);
      expect(c.notes.where((n) => RegExp('office|cell|fax|direct', caseSensitive: false).hasMatch(n)), isEmpty);
    });

    test('a word in front of the next number still labels that number', () {
      final c = parseCard(OcrPage.fromText(['Theo Vance', '330-555-0190 Fax 330-555-0191']));
      expect(c.phones.length, 1);
      expect(c.faxes.length, 1);
    });
  });

  group('sweep crops', () {
    test('the margin grows the outline a little about its centre', () {
      final q = Quad([const Pt(100, 100), const Pt(300, 100), const Pt(300, 200), const Pt(100, 200)]);
      final g = growQuad(q, sweepCropMargin);
      expect(g.tl.x, closeTo(97, 0.01));
      expect(g.br.y, closeTo(201.5, 0.01));
    });

    test('hashes of one card are close, of another far', () {
      expect(hammingDistance(0, 0), 0);
      expect(hammingDistance(0xFF, 0x0F), 4);
      expect(hammingDistance(-1, 0), 64);
    });
  });
}
