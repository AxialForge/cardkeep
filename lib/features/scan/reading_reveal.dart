import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../parser/ocr.dart';
import '../../scan/scan_pipeline.dart';
import 'review_panel.dart';

/// The captured card with a short "reading" animation: a scan line sweeps the
/// card, every line of text it passes gets a faint box, then the lines that
/// became contact details light up one by one in their field colour with a
/// label (Name, Phone...). Shows the end state at once when the phone asks for
/// reduced motion.
class CardReadingReveal extends ConsumerStatefulWidget {
  final ScannedSide side;
  final double height;
  const CardReadingReveal({super.key, required this.side, this.height = 200});

  @override
  ConsumerState<CardReadingReveal> createState() => _CardReadingRevealState();
}

class _CardReadingRevealState extends ConsumerState<CardReadingReveal> with SingleTickerProviderStateMixin {
  static const sweep = 0.45; // fraction of the animation spent sweeping
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  Size? _size;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = ref.watch(imageStoreProvider).value?.rectified(widget.side.hash);
    final hasFile = file != null && file.existsSync();
    if (hasFile && _size == null) {
      cardImageSize(file).then((s) {
        if (mounted) setState(() => _size = s);
      });
    }
    final image = hasFile
        ? Image.file(file, fit: BoxFit.fill, semanticLabel: 'Captured card')
        : Image.memory(widget.side.thumb, fit: BoxFit.fill, semanticLabel: 'Captured card');
    final size = _size;
    final lines = widget.side.ocr?.lines ?? const <OcrLine>[];
    if (size == null || lines.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Tokens.radiusSm),
          child: Image.memory(widget.side.thumb, fit: BoxFit.contain, semanticLabel: 'Captured card'),
        ),
      );
    }

    final parsed = widget.side.parsed;
    final fields = [for (final l in lines) fieldOfLine(parsed, l)];
    // Highlight order: top to bottom among the lines that became details.
    final found = [
      for (var i = 0; i < lines.length; i++)
        if (fields[i] != null) i,
    ]..sort((a, b) => lines[a].top.compareTo(lines[b].top));
    // One label per field, on the first (topmost) line that became it.
    final labelFor = <int, String>{};
    final seen = <CardField>{};
    for (final i in found) {
      if (seen.add(fields[i]!)) labelFor[i] = fields[i]!.label;
    }
    final qrBoxes = widget.side.qrBoxes;

    return SizedBox(
      height: widget.height,
      child: Center(
        child: AspectRatio(
          aspectRatio: size.width / size.height,
          child: LayoutBuilder(
            builder: (context, box) {
              final sx = box.maxWidth / size.width, sy = box.maxHeight / size.height;
              Rect rectOf(double l, double t, double w, double h) =>
                  Rect.fromLTWH(l * sx - 2, t * sy - 2, w * sx + 4, h * sy + 4);
              final rects = [for (final l in lines) rectOf(l.left, l.top, l.width, l.height)];
              final qrRects = [for (final q in qrBoxes) rectOf(q.$1, q.$2, q.$3, q.$4)];
              final labels = placeLabels(
                [...rects, ...qrRects],
                {...labelFor, for (var i = 0; i < qrRects.length; i++) rects.length + i: 'QR'},
                box.biggest,
              );
              return AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = _c.value;
                  final scanY = (t / sweep).clamp(0.0, 1.0) * box.maxHeight;
                  final reveal = ((t - sweep) / (1 - sweep)).clamp(0.0, 1.0);
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(Tokens.radiusSm),
                    child: Stack(
                      children: [
                        Positioned.fill(child: image),
                        for (var i = 0; i < lines.length; i++)
                          ..._box(rects[i], lines[i], fields[i], scanY, found, reveal, labels[i]),
                        // QR codes get their own box once the reading is done.
                        if (reveal > 0)
                          for (var i = 0; i < qrRects.length; i++)
                            ..._tagged(qrRects[i], qrColor, reveal, labels[rects.length + i], 'QR'),
                        if (t < sweep)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: scanY - 18,
                            height: 20,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Tokens.brandOrange.withValues(alpha: 0),
                                      Tokens.brandOrange.withValues(alpha: 0.35),
                                    ],
                                  ),
                                  border: const Border(bottom: BorderSide(color: Tokens.brandOrange, width: 2)),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _box(Rect rect, OcrLine l, CardField? field, double scanY, List<int> found, double reveal, Rect? label) {
    if (scanY < rect.top + 2) return const [];
    final rank = found.indexWhere((i) => identical(widget.side.ocr!.lines[i], l));
    // Each found line gets its slot in the reveal phase; overlapping fades.
    final n = math.max(found.length, 1);
    final p = rank < 0 ? 0.0 : ((reveal * (n + 1) - rank)).clamp(0.0, 1.0);
    final color = p > 0 ? fieldColor(field) : Tokens.ink2;
    return _tagged(rect, color, p, p > 0 && field != null ? label : null, field?.label ?? '');
  }

  /// A box with its tag at [label] (none when there was no room for one).
  List<Widget> _tagged(Rect rect, Color color, double p, Rect? label, String text) {
    return [
      Positioned.fromRect(
        rect: rect,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08 + 0.22 * p),
              border: Border.all(
                color: color.withValues(alpha: 0.5 + 0.5 * p),
                width: 1 + p,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
      if (label != null)
        Positioned.fromRect(
          rect: label,
          child: IgnorePointer(
            child: Opacity(
              opacity: p,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700, height: 1.1),
                ),
              ),
            ),
          ),
        ),
    ];
  }
}

/// Colour of the box round a QR code.
const qrColor = Color(0xFF6A4C93);

/// Below this shown width the card is too small for tags: boxes only.
const minWidthForLabels = 240.0;

/// Size of a field tag for [text] (9.5 pt bold, 4 px side padding).
Size labelSize(String text) => Size(9 + text.length * 6.0, 14);

/// Where each tag goes (phone test F6). [want] maps a box index in [boxes] to
/// its tag text. A tag goes beside its box, else above, below or to its left:
/// the first spot inside [area] that covers no other box and no tag already
/// placed. A tag with no free spot is left out rather than drawn over text; on
/// a small image no tags are shown at all.
Map<int, Rect> placeLabels(List<Rect> boxes, Map<int, String> want, Size area) {
  if (area.width < minWidthForLabels) return const {};
  final placed = <int, Rect>{};
  final keys = want.keys.toList()..sort((a, b) => boxes[a].top.compareTo(boxes[b].top));
  for (final i in keys) {
    final b = boxes[i];
    final s = labelSize(want[i]!);
    final spots = [
      Rect.fromLTWH(b.right + 4, b.center.dy - s.height / 2, s.width, s.height),
      Rect.fromLTWH(b.left, b.top - s.height - 1, s.width, s.height),
      Rect.fromLTWH(b.left, b.bottom + 1, s.width, s.height),
      Rect.fromLTWH(b.left - s.width - 4, b.center.dy - s.height / 2, s.width, s.height),
    ];
    for (final r in spots) {
      if (r.left < 0 || r.top < 0 || r.right > area.width || r.bottom > area.height) continue;
      var free = true;
      for (var j = 0; j < boxes.length && free; j++) {
        if (j != i && boxes[j].deflate(1).overlaps(r)) free = false;
      }
      if (free && placed.values.any((p) => p.inflate(1).overlaps(r))) free = false;
      if (free) {
        placed[i] = r;
        break;
      }
    }
  }
  return placed;
}
