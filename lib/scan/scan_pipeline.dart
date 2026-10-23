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
import 'qr_content.dart';
import 'quality.dart';

/// Reads QR codes from an image file. ML Kit on phones; null elsewhere.
abstract class QrReader {
  Future<List<String>> read(String imagePath);

  /// Payloads with where each code sits (image pixels: left, top, width,
  /// height), for the QR box on the review image. Readers without positions
  /// return the payloads alone.
  Future<List<(String, QrBox?)>> readWithBoxes(String imagePath) async => [
    for (final r in await read(imagePath)) (r, null),
  ];
}

typedef QrBox = (double, double, double, double);

/// One card side after capture: stored on disk and read. Serialisable, so a
/// card waiting in the review queue survives an app restart; the parse and the
/// QR merge are recomputed from the stored OCR lines.
class ScannedSide {
  final String hash;
  final Uint8List thumb;
  final List<QualityIssue> issues;
  final bool manualCrop;
  final OcrPage? ocr;
  final bool enhancedPass; // the contrast/inverted pass read better
  final List<String> qrRaw; // every QR payload found on the card
  final String region;
  final String? logo; // hash of the logo cut from this side (ImageStore.logo)
  final List<QrBox> qrBoxes; // where the QR codes are, for their box on the review image

  ScannedSide({
    required this.hash,
    required this.thumb,
    required this.issues,
    this.manualCrop = false,
    this.ocr,
    this.enhancedPass = false,
    this.qrRaw = const [],
    this.region = 'US',
    this.logo,
    this.qrBoxes = const [],
  });

  late final List<QrContent> qr = [for (final r in qrRaw) QrContent.classify(r)];
  QrContent? get qrContact => qr.where((q) => q.kind == QrKind.contact).firstOrNull;
  QrContent? get qrLink => qr.where((q) => q.kind == QrKind.link).firstOrNull;

  late final ParsedCard? ocrParsed = ocr == null ? null : parseCard(ocr!, region: region);

  /// QR contact merged over OCR (structured wins); or OCR alone.
  late final (ParsedCard?, Set<String>) _merged = () {
    final structured = qrContact?.toParsed();
    final merged = structured == null ? (ocrParsed, const <String>{}) : mergeStructured(structured, ocrParsed);
    // A plain web link in a QR code is the website when the text has none.
    final url = qrLink?.url;
    final p = merged.$1;
    if (url != null && p != null && (p.website == null || p.website!.value.trim().isEmpty)) {
      p.website = ParsedField(url.toString(), 0.9);
    }
    return merged;
  }();

  ParsedCard? get parsed => _merged.$1;

  /// Fields to mark amber: the parser was unsure, or QR and OCR disagree.
  Set<String> get check =>
      {...uncertainFields(qrContact == null ? parsed : ocrParsed), ..._merged.$2}
        ..removeWhere((f) => qrContact != null && !_merged.$2.contains(f) && _qrHas(f));

  bool _qrHas(String field) {
    final c = qrContact?.toParsed();
    if (c == null) return false;
    return switch (field) {
      'name' => c.name != null,
      'title' => c.title != null,
      'company' => c.company != null,
      'website' => c.website != null,
      'address' => c.address != null,
      'email' => c.emails.isNotEmpty,
      'phone' => c.phones.isNotEmpty,
      _ => false,
    };
  }

  Map<String, Object?> toJson() => {
    'ocr': ocr?.toJson(),
    'enhanced': enhancedPass,
    'issues': [for (final i in issues) i.name],
    'manualCrop': manualCrop,
    'qr': qrRaw,
    'region': region,
    'logo': ?logo,
    if (qrBoxes.isNotEmpty)
      'qrBoxes': [
        for (final b in qrBoxes) [b.$1, b.$2, b.$3, b.$4],
      ],
  };

  static ScannedSide fromJson(String hash, Uint8List thumb, Map<String, Object?> j) => ScannedSide(
    hash: hash,
    thumb: thumb,
    issues: [
      for (final n in (j['issues'] as List?) ?? const []) ?QualityIssue.values.where((v) => v.name == n).firstOrNull,
    ],
    manualCrop: j['manualCrop'] == true,
    ocr: j['ocr'] is Map<String, Object?> ? OcrPage.fromJson(j['ocr']! as Map<String, Object?>) : null,
    enhancedPass: j['enhanced'] == true,
    qrRaw: [for (final q in (j['qr'] as List?) ?? const []) '$q'],
    region: (j['region'] as String?) ?? 'US',
    logo: j['logo'] as String?,
    qrBoxes: [
      for (final b in (j['qrBoxes'] as List?) ?? const [])
        if (b is List && b.length == 4)
          ((b[0] as num).toDouble(), (b[1] as num).toDouble(), (b[2] as num).toDouble(), (b[3] as num).toDouble()),
    ],
  );

  /// What cards.ocr_json holds for this side.
  String get ocrJson => jsonEncode(toJson());
}

/// Capture -> store -> OCR + QR -> parse (spec §6). Image work runs in an
/// isolate; OCR and QR run on the platform side (ML Kit).
class ScanPipeline {
  final ImageStore store;
  final OcrAdapter? ocr; // null where ML Kit isn't available (desktop, tests)
  final QrReader? qr;
  final String region;

  ScanPipeline({required this.store, required this.ocr, this.qr, required this.region});

  /// Processes one photo. Returns one side per card found (several in pile mode).
  /// The saved capture is removed at the end; callers that store the cards
  /// afterwards use [processKeeping] instead.
  Future<List<ScannedSide>> process(Uint8List jpeg, {bool pile = false, Quad? corners}) async {
    final (sides, pending) = await processKeeping(jpeg, pile: pile, corners: corners);
    await store.donePending(pending);
    return sides;
  }

  /// Like [process], but the saved capture in pending/ is kept and returned:
  /// the caller deletes it ([ImageStore.donePending]) only after the cards are in
  /// the review queue, so a kill in between loses nothing (audit MOB-REL-0002).
  Future<(List<ScannedSide>, File)> processKeeping(
    Uint8List jpeg, {
    bool pile = false,
    Quad? corners,
    File? pending,
  }) async {
    pending ??= await store.savePending(jpeg); // never lose a capture
    final r = await compute(_processInIsolate, (jpeg, pile, corners));
    final sides = <ScannedSide>[];
    for (final found in r.cards) {
      var card = found;
      var hash = await store.commit(originalJpeg: r.original, rectifiedJpeg: card.jpeg, thumbJpeg: card.thumbJpeg);
      var read = await _readSafely(hash, card.jpeg);
      // A pile cut-out turned to landscape may be upside down: try it the other
      // way round and keep whichever reads better.
      if (card.turned && (read == null || _score(read.$1) < 0.6)) {
        final flipped = await compute(_flip, card);
        final h2 = await store.commit(
          originalJpeg: r.original,
          rectifiedJpeg: flipped.jpeg,
          thumbJpeg: flipped.thumbJpeg,
        );
        final read2 = await _readSafely(h2, flipped.jpeg);
        if (read2 != null && (read == null || _score(read2.$1) > _score(read.$1))) {
          await store.delete(hash);
          (card, hash, read) = (flipped, h2, read2);
        } else {
          await store.delete(h2);
        }
      }
      // Any other cut (single capture, Adjust corners) can come out sideways or
      // upside down when the card was held at an angle: try the other turns and
      // keep whichever reads clearly better. A real portrait card reads best
      // as it is, so it stays (phone test F36).
      if (!card.turned) {
        final portrait = await compute(isPortraitJpeg, card.jpeg);
        final first = read == null ? 0.0 : _score(read.$1);
        final tries = portrait ? const [90, 270] : (first < 0.6 ? const [180] : const <int>[]);
        final scores = <int, double>{0: first};
        final tried = <int, (RectifiedCard, String, (OcrPage, bool)?)>{};
        for (final deg in tries) {
          final turned = await compute(_rotate, (card, deg));
          final h = await store.commit(
            originalJpeg: r.original,
            rectifiedJpeg: turned.jpeg,
            thumbJpeg: turned.thumbJpeg,
          );
          final rd = await _readSafely(h, turned.jpeg);
          scores[deg] = rd == null ? 0.0 : _score(rd.$1);
          tried[deg] = (turned, h, rd);
        }
        final best = bestRotation(scores);
        for (final e in tried.entries) {
          if (e.key == best) {
            await store.delete(hash);
            (card, hash, read) = e.value;
          } else {
            await store.delete(e.value.$2);
          }
        }
      }
      // No card outline found: cut to the text instead of keeping the whole
      // photo, so the card fills the image.
      if (card.manualCrop && corners == null && read != null && read.$1.lines.length >= 2) {
        final cropped = await compute(_cropToText, (
          card,
          [for (final l in read.$1.lines) (l.left, l.top, l.width, l.height)],
        ));
        if (cropped != null) {
          final h2 = await store.commit(
            originalJpeg: r.original,
            rectifiedJpeg: cropped.jpeg,
            thumbJpeg: cropped.thumbJpeg,
          );
          final read2 = await _readSafely(h2, cropped.jpeg);
          if (read2 != null) {
            await store.delete(hash);
            (card, hash, read) = (cropped, h2, read2);
          } else {
            await store.delete(h2);
          }
        }
      }
      final hits = await _qr(hash);
      final codes = [for (final h in hits) h.$1];
      final logo = await _logo(card.jpeg, read?.$1, [for (final h in hits) ?h.$2]);
      sides.add(
        ScannedSide(
          hash: hash,
          thumb: card.thumbJpeg,
          issues: card.issues,
          manualCrop: card.manualCrop,
          ocr: read?.$1,
          enhancedPass: read?.$2 ?? false,
          qrRaw: codes,
          region: region,
          logo: logo,
          qrBoxes: [for (final h in hits) ?h.$2],
        ),
      );
    }
    return (sides, pending);
  }

  /// Cuts the logo out once the text lines are known (they and any QR code
  /// are masked out).
  Future<String?> _logo(Uint8List rectified, OcrPage? page, [List<QrBox> qrBoxes = const []]) async {
    try {
      final boxes = [for (final l in page?.lines ?? const <OcrLine>[]) (l.left, l.top, l.width, l.height), ...qrBoxes];
      final jpeg = await compute(_extractLogo, (rectified, boxes));
      return jpeg == null ? null : await store.saveLogo(jpeg);
    } catch (e) {
      debugPrint('Logo failed: $e');
      return null; // a logo is a nicety; never block a card
    }
  }

  Future<List<(String, QrBox?)>> _qr(String hash) async {
    final reader = qr;
    if (reader == null) return const [];
    try {
      return await reader.readWithBoxes(store.rectified(hash).path);
    } catch (_) {
      return const []; // a QR failure never blocks a card
    }
  }

  /// A failing text reader never loses the card: it is kept without text and
  /// can be filled in by hand (or re-read later).
  Future<(OcrPage, bool)?> _readSafely(String hash, Uint8List rectified) async {
    try {
      return await _read(hash, rectified);
    } catch (e) {
      debugPrint('OCR failed: $e');
      return null;
    }
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

  /// OCR of one region of a stored card ("Read a region" on the review screen).
  Future<String> readRegion(
    String hash, {
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) async {
    final engine = ocr;
    if (engine == null) return '';
    final crop = await compute(_cropJpeg, (await store.rectified(hash).readAsBytes(), left, top, right, bottom));
    final tmp = File(p.join(Directory.systemTemp.path, 'ck_region_${DateTime.now().microsecondsSinceEpoch}.jpg'));
    await tmp.writeAsBytes(crop, flush: true);
    try {
      final page = await engine.recognize(tmp.path);
      return page.lines.map((l) => l.text.trim()).where((t) => t.isNotEmpty).join(' ');
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

Uint8List? _extractLogo((Uint8List, List<(double, double, double, double)>) a) => extractLogo(a.$1, a.$2);

RectifiedCard _flip(RectifiedCard c) => rotateCard(c, 180);

RectifiedCard _rotate((RectifiedCard, int) a) => rotateCard(a.$1, a.$2);

/// The turn (0, 90, 180, 270) whose reading scored best. The card as captured
/// (0) keeps it unless another turn reads clearly better, by more than 0.1.
int bestRotation(Map<int, double> scores) {
  final base = scores[0] ?? 0;
  var best = 0;
  var top = base + 0.1;
  for (final e in scores.entries) {
    if (e.key != 0 && e.value > top) {
      best = e.key;
      top = e.value;
    }
  }
  return best;
}

RectifiedCard? _cropToText((RectifiedCard, List<(double, double, double, double)>) a) => cropToText(a.$1, a.$2);

Uint8List _cropJpeg((Uint8List, double, double, double, double) a) =>
    cropJpeg(a.$1, left: a.$2, top: a.$3, right: a.$4, bottom: a.$5);

/// Parser output -> edit form. The back side fills gaps the front left (spec
/// §2.8). On a conflict the surer reading wins, the front on a tie: a printed
/// "Becker Pumps Corporation" on the back beats a logo word guessed on the front (F7).
ContactDraft draftFromScan(ParsedCard? front, [ParsedCard? back]) {
  final d = ContactDraft();
  ParsedField? pick(ParsedField? f, ParsedField? b) =>
      f == null ? b : (b != null && b.confidence > f.confidence + 0.05 ? b : f);
  final name = pick(front?.name, back?.name)?.value.trim() ?? '';
  if (name.isNotEmpty) {
    // "Dana K. Reyes": first, middle (name or initial), last.
    final parts = name.split(RegExp(r'\s+'));
    d.first = parts.first;
    d.middle = parts.length > 2 ? parts.sublist(1, parts.length - 1).join(' ') : '';
    d.last = parts.length > 1 ? parts.last : '';
  }
  d.title = pick(front?.title, back?.title)?.value ?? d.title;
  d.company = pick(front?.company, back?.company)?.value ?? d.company;
  d.website = pick(front?.website, back?.website)?.value ?? d.website;
  d.address = pick(front?.address, back?.address)?.value ?? d.address;
  final phones = <LabeledValue>[];
  final emails = <String>[];
  final notes = <String>[];
  for (final c in [front, back]) {
    if (c == null) continue;
    for (final ph in c.phones) {
      if (phones.every((x) => x.value != ph.value)) {
        phones.add(LabeledValue(ph.label == 'mobile' ? 'Mobile' : 'Office', ph.value, ph.extension));
      }
    }
    for (final f in c.faxes) {
      if (d.faxes.every((x) => x.value != f.value)) d.faxes.add(LabeledValue('Fax', f.value, f.extension));
    }
    for (final e in c.extras) {
      if (d.extras.every((x) => x.value != e.value)) d.extras.add(LabeledValue(e.label, e.value));
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

/// Auto-save rule (deep dive §2.11): a name, a phone or email, every required
/// field confident, nothing to check and no capture problems. The duplicate/
/// job-change check is added by S8.
///
/// The bar is [autoSaveConfidence], not the 0.85 rule weight: a field score
/// mixes OCR confidence in (0.5 x OCR + 0.3 x rule + 0.2 x cross-check), so a
/// clearly read card with OCR around 0.8 scored ~0.82 and nothing was ever
/// saved automatically (phone test F16).
const autoSaveConfidence = 0.75;

const _required = {'name', 'phone', 'email'};

bool isCleanCard(ScannedSide s) {
  final c = s.parsed;
  if (c == null || c.name == null || c.name!.value.trim().isEmpty) return false;
  if (c.phones.isEmpty && c.emails.isEmpty) return false;
  // Only the fields that make the contact count here: a company guessed from
  // the email domain is always amber, and blocked every card (F16).
  if (s.check.any(_required.contains) || s.issues.isNotEmpty || s.manualCrop) return false;
  final required = [c.name!, ...c.phones, ...c.emails];
  return required.every((f) => f.confidence >= autoSaveConfidence);
}
