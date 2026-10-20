import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/contacts/contact_models.dart';
import '../core/images/image_store.dart';
import '../parser/ocr.dart';
import '../parser/rules.dart';
import 'card_detector.dart';
import 'geometry.dart';
import 'quality.dart';

/// One card side after capture: stored on disk, read and parsed.
class ScannedSide {
  final String hash;
  final Uint8List thumb;
  final List<QualityIssue> issues;
  final bool manualCrop;
  final OcrPage? ocr;
  final ParsedCard? parsed;
  final bool enhancedPass; // the contrast/inverted pass read better

  const ScannedSide({
    required this.hash,
    required this.thumb,
    required this.issues,
    this.manualCrop = false,
    this.ocr,
    this.parsed,
    this.enhancedPass = false,
  });

  /// Stored in cards.ocr_json so a card can be re-parsed later without re-running OCR.
  String get ocrJson => jsonEncode({if (ocr != null) ...ocr!.toJson(), 'enhanced': enhancedPass});
}

/// Capture -> store -> OCR -> parse (spec §6). Image work runs in an isolate;
/// OCR runs on the platform side (ML Kit).
class ScanPipeline {
  final ImageStore store;
  final OcrAdapter? ocr; // null where ML Kit isn't available (desktop, tests)
  final String region;

  ScanPipeline({required this.store, required this.ocr, required this.region});

  /// Processes one photo. Returns one side per card found (several in pile mode).
  Future<List<ScannedSide>> process(Uint8List jpeg, {bool pile = false, Quad? corners}) async {
    final pending = await store.savePending(jpeg); // never lose a capture
    final r = await compute(_processInIsolate, (jpeg, pile, corners));
    final sides = <ScannedSide>[];
    for (final (i, card) in r.cards.indexed) {
      final hash = await store.commit(
        originalJpeg: r.original,
        rectifiedJpeg: card.jpeg,
        thumbJpeg: card.thumbJpeg,
        pending: i == r.cards.length - 1 ? pending : null,
      );
      final read = await _read(hash, card.jpeg);
      sides.add(
        ScannedSide(
          hash: hash,
          thumb: card.thumbJpeg,
          issues: card.issues,
          manualCrop: card.manualCrop,
          ocr: read?.$1,
          parsed: read == null ? null : parseCard(read.$1, region: region),
          enhancedPass: read?.$2 ?? false,
        ),
      );
    }
    return sides;
  }

  /// OCR pass 1 as-is; pass 2 on a contrast-enhanced (and, for dark cards,
  /// inverted) copy when pass 1 is weak. Keeps the better page.
  Future<(OcrPage, bool)?> _read(String hash, Uint8List rectified) async {
    final engine = ocr;
    if (engine == null) return null;
    final first = await engine.recognize(store.rectified(hash).path);
    if (_score(first) >= 0.8 && first.lines.length >= 3) return (first, false);
    final dark = await compute(isDarkCard, rectified);
    final enhanced = await compute(_enhance, (rectified, dark));
    final tmp = File(p.join(Directory.systemTemp.path, 'ck_ocr_$hash.jpg'));
    await tmp.writeAsBytes(enhanced, flush: true);
    try {
      final second = await engine.recognize(tmp.path);
      return _score(second) > _score(first) ? (second, true) : (first, false);
    } finally {
      if (tmp.existsSync()) await tmp.delete();
    }
  }

  /// Mean line confidence when the engine reports it; otherwise a proxy from
  /// how much text was found (ML Kit Flutter confidence is unconfirmed).
  static double _score(OcrPage page) {
    final known = page.lines.where((l) => l.confidence != null).toList();
    if (known.isNotEmpty) return known.map((l) => l.confidence!).reduce((a, b) => a + b) / known.length;
    final chars = page.lines.fold<int>(0, (n, l) => n + l.text.trim().length);
    return (chars / 120).clamp(0, 1).toDouble();
  }
}

({Uint8List original, List<RectifiedCard> cards, int width, int height}) _processInIsolate(
  (Uint8List, bool, Quad?) a,
) => processStill(a.$1, allCards: a.$2, corners: a.$3);

Uint8List _enhance((Uint8List, bool) a) => enhanceForOcr(a.$1, invert: a.$2);

/// Parser output -> edit form. The back side fills gaps the front left (spec
/// §2.8): the front wins on conflicts.
ContactDraft draftFromScan(ParsedCard? front, [ParsedCard? back]) {
  final d = ContactDraft();
  for (final c in [back, front]) {
    if (c == null) continue;
    final name = c.name?.value.trim() ?? '';
    if (name.isNotEmpty) {
      final parts = name.split(RegExp(r'\s+'));
      d.first = parts.length > 1 ? parts.sublist(0, parts.length - 1).join(' ') : parts.first;
      d.last = parts.length > 1 ? parts.last : '';
    }
    if (c.title != null) d.title = c.title!.value;
    if (c.company != null) d.company = c.company!.value;
    if (c.website != null) d.website = c.website!.value;
    if (c.address != null) d.address = c.address!.value;
  }
  final phones = <LabeledValue>[];
  final emails = <String>[];
  final notes = <String>[];
  for (final c in [front, back]) {
    if (c == null) continue;
    for (final ph in c.phones) {
      if (phones.every((x) => x.value != ph.value)) {
        phones.add(LabeledValue(ph.label == 'mobile' ? 'Mobile' : 'Office', ph.value));
      }
    }
    for (final e in c.emails) {
      if (!emails.contains(e.value)) emails.add(e.value);
    }
    if (c.suffix != null) notes.add('Credentials: ${c.suffix!.value}');
    notes.addAll(c.notes.where((n) => n.trim().isNotEmpty));
  }
  d.phones = phones.isEmpty ? [const LabeledValue('Mobile', '')] : phones;
  d.emails = emails.isEmpty ? [''] : emails;
  d.notes = notes.join('\n');
  return d;
}

/// Field names on the edit form that the parser was unsure about (< 0.7),
/// shown amber so they're checked first.
Set<String> uncertainFields(ParsedCard? c) {
  if (c == null) return const {};
  return {
    if (c.name?.needsReview ?? false) 'name',
    if (c.title?.needsReview ?? false) 'title',
    if (c.company?.needsReview ?? false) 'company',
    if (c.website?.needsReview ?? false) 'website',
    if (c.address?.needsReview ?? false) 'address',
    if (c.emails.any((e) => e.needsReview)) 'email',
    if (c.phones.any((e) => e.needsReview)) 'phone',
  };
}
