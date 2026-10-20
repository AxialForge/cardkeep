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

    return SizedBox(
      height: widget.height,
      child: Center(
        child: AspectRatio(
          aspectRatio: size.width / size.height,
          child: LayoutBuilder(
            builder: (context, box) {
              final sx = box.maxWidth / size.width, sy = box.maxHeight / size.height;
              return AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = _c.value;
                  final labelled = <CardField>{}; // one label per field, per frame
                  final scanY = (t / sweep).clamp(0.0, 1.0) * box.maxHeight;
                  final reveal = ((t - sweep) / (1 - sweep)).clamp(0.0, 1.0);
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(Tokens.radiusSm),
                    child: Stack(
                      children: [
                        Positioned.fill(child: image),
                        for (var i = 0; i < lines.length; i++)
                          ..._box(lines[i], fields[i], sx, sy, scanY, found, reveal, labelled, box.maxWidth),
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

  List<Widget> _box(
    OcrLine l,
    CardField? field,
    double sx,
    double sy,
    double scanY,
    List<int> found,
    double reveal,
    Set<CardField> labelled,
    double width,
  ) {
    final top = l.top * sy;
    if (scanY < top) return const [];
    final rank = found.indexWhere((i) => identical(widget.side.ocr!.lines[i], l));
    // Each found line gets its slot in the reveal phase; overlapping fades.
    final n = math.max(found.length, 1);
    final p = rank < 0 ? 0.0 : ((reveal * (n + 1) - rank)).clamp(0.0, 1.0);
    final color = p > 0 ? fieldColor(field) : Tokens.ink2;
    final rect = Rect.fromLTWH(l.left * sx - 2, top - 2, l.width * sx + 4, l.height * sy + 4);
    final showLabel = p > 0 && field != null && labelled.add(field);
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
      if (showLabel)
        Positioned(
          // Beside the text when there is room (cards are mostly left-aligned),
          // else above it; stacked lines would hide each other's labels.
          left: rect.right + 64 < width ? rect.right + 4 : rect.left,
          top: rect.right + 64 < width ? rect.center.dy - 7 : math.max(0, rect.top - 15),
          child: Opacity(
            opacity: p,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
              child: Text(
                field.label,
                style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700, height: 1.1),
              ),
            ),
          ),
        ),
    ];
  }
}
