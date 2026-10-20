import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../parser/ocr.dart';
import '../../parser/rules.dart';
import '../../scan/qr_content.dart';
import '../../scan/scan_pipeline.dart';

/// Fields a piece of card text can be assigned to.
enum CardField {
  name('Name'),
  title('Title'),
  company('Company'),
  phone('Phone'),
  email('Email'),
  website('Website'),
  address('Address'),
  notes('Notes');

  final String label;
  const CardField(this.label);
}

/// The scanned card with a tappable box on every line of text (deep dive
/// §2.10): tap a box, then pick its field. "Read a region" OCRs a box you draw.
class ReviewCardPanel extends ConsumerStatefulWidget {
  final ScannedSide side;
  final void Function(CardField field, String text) onAssign;
  const ReviewCardPanel({super.key, required this.side, required this.onAssign});

  @override
  ConsumerState<ReviewCardPanel> createState() => _ReviewCardPanelState();
}

class _ReviewCardPanelState extends ConsumerState<ReviewCardPanel> {
  String? _selected;
  bool _drawing = false;
  Offset? _dragStart, _dragEnd; // in image fractions
  bool _reading = false;

  /// Which field each OCR line ended up in, for colouring its box.
  CardField? _fieldOf(OcrLine l) {
    final p = widget.side.parsed;
    if (p == null) return null;
    final t = l.text.toLowerCase();
    bool has(ParsedField? f) => f != null && t.contains(f.value.toLowerCase().split(',').first.trim());
    if (has(p.name)) return CardField.name;
    if (has(p.title)) return CardField.title;
    if (has(p.company)) return CardField.company;
    if (p.emails.any(has)) return CardField.email;
    if (has(p.website)) return CardField.website;
    if (p.address != null && p.address!.value.toLowerCase().contains(t.trim())) return CardField.address;
    if (RegExp(r'\d{3}.*\d{4}').hasMatch(t)) return CardField.phone;
    return null;
  }

  Color _colorOf(CardField? f) => switch (f) {
    CardField.name => Tokens.brandOrange,
    CardField.title || CardField.company => Tokens.coldFg,
    CardField.phone || CardField.email || CardField.website => const Color(0xFF2F7D4F),
    CardField.address => Tokens.amberFg,
    _ => Tokens.ink2,
  };

  Future<void> _readRegion() async {
    final a = _dragStart, b = _dragEnd;
    setState(() => _drawing = false);
    if (a == null || b == null) return;
    setState(() => _reading = true);
    final pipeline = await ref.read(scanPipelineProvider.future);
    final text = await pipeline.readRegion(
      widget.side.hash,
      left: a.dx < b.dx ? a.dx : b.dx,
      top: a.dy < b.dy ? a.dy : b.dy,
      right: a.dx > b.dx ? a.dx : b.dx,
      bottom: a.dy > b.dy ? a.dy : b.dy,
    );
    if (!mounted) return;
    setState(() {
      _reading = false;
      _dragStart = _dragEnd = null;
      _selected = text.isEmpty ? null : text;
    });
    if (text.isEmpty) showMessage(context, 'No text found there. Try a bigger box.');
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(imageStoreProvider).value;
    final file = store?.rectified(widget.side.hash);
    final lines = widget.side.ocr?.lines ?? const <OcrLine>[];
    final link = widget.side.qrLink;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (file != null && file.existsSync())
            FutureBuilder<Size>(
              future: _imageSize(file),
              builder: (context, snap) {
                final size = snap.data;
                if (size == null) return const SizedBox(height: 180);
                return AspectRatio(
                  aspectRatio: size.width / size.height,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final sx = box.maxWidth / size.width, sy = box.maxHeight / size.height;
                      Offset frac(Offset p) =>
                          Offset((p.dx / box.maxWidth).clamp(0, 1), (p.dy / box.maxHeight).clamp(0, 1));
                      return GestureDetector(
                        onPanStart: _drawing
                            ? (d) => setState(() => _dragStart = _dragEnd = frac(d.localPosition))
                            : null,
                        onPanUpdate: _drawing ? (d) => setState(() => _dragEnd = frac(d.localPosition)) : null,
                        onPanEnd: _drawing ? (_) => _readRegion() : null,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(file, fit: BoxFit.fill, semanticLabel: 'Scanned card'),
                              ),
                            ),
                            if (!_drawing)
                              for (final l in lines)
                                Positioned(
                                  left: l.left * sx - 2,
                                  top: l.top * sy - 2,
                                  width: l.width * sx + 4,
                                  height: l.height * sy + 4,
                                  child: Semantics(
                                    button: true,
                                    label: 'Card text: ${l.text}',
                                    child: GestureDetector(
                                      onTap: () => setState(() => _selected = l.text.trim()),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: _colorOf(_fieldOf(l))
                                              .withValues(alpha: _selected == l.text.trim() ? 0.30 : 0.10),
                                          border: Border.all(
                                            color: _colorOf(_fieldOf(l)),
                                            width: _selected == l.text.trim() ? 2 : 1,
                                          ),
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            if (_drawing && _dragStart != null && _dragEnd != null)
                              Positioned.fromRect(
                                rect: Rect.fromPoints(
                                  Offset(_dragStart!.dx * box.maxWidth, _dragStart!.dy * box.maxHeight),
                                  Offset(_dragEnd!.dx * box.maxWidth, _dragEnd!.dy * box.maxHeight),
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Tokens.brandOrange.withValues(alpha: 0.15),
                                    border: Border.all(color: Tokens.brandOrange, width: 2),
                                  ),
                                ),
                              ),
                            if (_reading) const Center(child: CircularProgressIndicator()),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _drawing
                      ? 'Drag a box over the text to read.'
                      : 'Tap a text block on the card, then choose its field.',
                  style: AppText.secondary.copyWith(fontSize: 12.5),
                ),
              ),
              TextButton.icon(
                onPressed: lines.isEmpty && widget.side.ocr == null
                    ? null
                    : () => setState(() {
                        _drawing = !_drawing;
                        _dragStart = _dragEnd = null;
                      }),
                icon: Icon(_drawing ? Icons.close : Icons.crop_free, size: 18),
                label: Text(_drawing ? 'Cancel' : 'Read a region'),
              ),
            ],
          ),
          if (_selected != null) ...[
            const Divider(height: 20),
            Row(
              children: [
                const Overline('Selected'),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_selected!, style: AppText.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  tooltip: 'Clear selection',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _selected = null),
                ),
              ],
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in CardField.values)
                  ActionChip(
                    label: Text(f.label),
                    onPressed: () {
                      widget.onAssign(f, _selected!);
                      setState(() => _selected = null);
                    },
                  ),
              ],
            ),
          ],
          if (link?.url case final url?) _LinkBanner(url: url),
        ],
      ),
    );
  }

  static final _sizes = <String, Size>{};
  static Future<Size> _imageSize(File f) async {
    if (_sizes[f.path] case final s?) return s;
    final img = await decodeImageFromList(await f.readAsBytes());
    final s = Size(img.width.toDouble(), img.height.toDouble());
    img.dispose();
    return _sizes[f.path] = s;
  }
}

/// A web link from a QR code on the card: shown with its real domain and any
/// warning signs before it can be opened (deep dive §3.7). Never auto-opened.
class _LinkBanner extends ConsumerWidget {
  final Uri url;
  const _LinkBanner({required this.url});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final check = LinkCheck.of(url);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: check.warnings.isEmpty ? Tokens.selected : Tokens.amberBg,
          borderRadius: BorderRadius.circular(Tokens.radiusSm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.qr_code_2, size: 20, color: Tokens.ink),
                const SizedBox(width: 8),
                Expanded(child: Text('This card has a web link', style: AppText.bodyStrong)),
              ],
            ),
            const SizedBox(height: 6),
            Text(check.host, style: AppText.heading.copyWith(fontSize: 18)),
            for (final w in check.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('⚠ $w', style: AppText.secondary.copyWith(color: Tokens.amberFg)),
              ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => ref.read(launcherProvider).open(url),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Open in browser'),
            ),
          ],
        ),
      ),
    );
  }
}
