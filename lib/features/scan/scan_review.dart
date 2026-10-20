import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../scan/geometry.dart';
import '../../scan/scan_pipeline.dart';

/// What the scanner hands to the new-contact form.
class ScanHandoff {
  final String cardId; // the queued cards row
  final ScannedSide front;
  final ScannedSide? back;
  const ScanHandoff({required this.cardId, required this.front, this.back});
}

enum CaptureAction { use, addBack, crop, retake }

/// After one capture: the card, its reason chips, and what to do next.
Future<CaptureAction?> showCaptureSheet(BuildContext context, ScannedSide side) => showModalBottomSheet<CaptureAction>(
  context: context,
  isScrollControlled: true,
  builder: (c) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Tokens.radiusSm),
            child: Image.memory(side.thumb, fit: BoxFit.contain, height: 200, semanticLabel: 'Captured card'),
          ),
          const SizedBox(height: 12),
          _Summary(side),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.pop(c, CaptureAction.use),
            icon: const Icon(Icons.check),
            label: const Text('Use this card'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(c, CaptureAction.addBack),
            icon: const Icon(Icons.flip),
            label: const Text('Add the back side'),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => Navigator.pop(c, CaptureAction.crop),
                  icon: const Icon(Icons.crop_free),
                  label: const Text('Adjust corners'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => Navigator.pop(c, CaptureAction.retake),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retake'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  ),
);

class _Summary extends StatelessWidget {
  final ScannedSide side;
  const _Summary(this.side);

  @override
  Widget build(BuildContext context) {
    final p = side.parsed;
    final name = p?.name?.value;
    final sub = [p?.title?.value, p?.company?.value].whereType<String>().join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name ?? (side.ocr == null ? 'Card saved' : 'No name found'), style: AppText.heading),
        if (sub.isNotEmpty) Text(sub, style: AppText.secondary),
        if (side.ocr == null)
          Text('Text reading is not available on this device; fill in the details by hand.', style: AppText.secondary),
        if (side.issues.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // "No edges found" comes from the issues, so corners you set yourself clear it.
              for (final i in side.issues) Pill(i.chip, bg: Tokens.amberBg, fg: Tokens.amberFg),
            ],
          ),
        ],
      ],
    );
  }
}

/// Manual four-corner crop when no edges were found (white card on white
/// paper, card cut off by a phone case). Drag the corners; a magnifier shows
/// the point under your finger. Returns the re-processed side.
class ManualCropScreen extends ConsumerStatefulWidget {
  final ScannedSide side;
  const ManualCropScreen({super.key, required this.side});
  @override
  ConsumerState<ManualCropScreen> createState() => _ManualCropScreenState();
}

class _ManualCropScreenState extends ConsumerState<ManualCropScreen> {
  Uint8List? _original;
  Size? _imageSize;
  late List<Offset> _corners; // in image pixels: TL, TR, BR, BL
  int? _dragging;
  Offset? _magnifierAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = await ref.read(imageStoreProvider.future);
    final bytes = await store.original(widget.side.hash).readAsBytes();
    final decoded = await decodeImageFromList(bytes);
    final w = decoded.width.toDouble(), h = decoded.height.toDouble();
    decoded.dispose();
    if (!mounted) return;
    setState(() {
      _original = bytes;
      _imageSize = Size(w, h);
      _corners = [Offset(w * .1, h * .3), Offset(w * .9, h * .3), Offset(w * .9, h * .7), Offset(w * .1, h * .7)];
    });
  }

  Future<void> _apply() async {
    setState(() => _saving = true);
    final pipeline = await ref.read(scanPipelineProvider.future);
    final store = await ref.read(imageStoreProvider.future);
    final quad = Quad([for (final c in _corners) Pt(c.dx, c.dy)]);
    final sides = await pipeline.process(_original!, corners: quad);
    if (sides.first.hash != widget.side.hash) await store.delete(widget.side.hash);
    if (mounted) context.pop(sides.first);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Adjust corners')),
      body: _original == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text('Drag each corner onto a corner of the card.', style: AppText.secondary),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final img = _imageSize!;
                      final scale = (box.maxWidth / img.width).clamp(0, box.maxHeight / img.height).toDouble();
                      final shown = Size(img.width * scale, img.height * scale);
                      final origin = Offset((box.maxWidth - shown.width) / 2, (box.maxHeight - shown.height) / 2);
                      Offset toScreen(Offset p) => origin + p * scale;
                      Offset toImage(Offset s) {
                        final o = (s - origin) / scale;
                        return Offset(o.dx.clamp(0, img.width), o.dy.clamp(0, img.height));
                      }

                      return GestureDetector(
                        onPanStart: (d) {
                          var best = 0;
                          for (var i = 1; i < 4; i++) {
                            if ((toScreen(_corners[i]) - d.localPosition).distance <
                                (toScreen(_corners[best]) - d.localPosition).distance) {
                              best = i;
                            }
                          }
                          setState(() {
                            _dragging = best;
                            _magnifierAt = d.localPosition;
                          });
                        },
                        onPanUpdate: (d) => setState(() {
                          _corners[_dragging!] = toImage(d.localPosition);
                          _magnifierAt = d.localPosition;
                        }),
                        onPanEnd: (_) => setState(() {
                          _dragging = null;
                          _magnifierAt = null;
                        }),
                        child: Stack(
                          children: [
                            Positioned(
                              left: origin.dx,
                              top: origin.dy,
                              width: shown.width,
                              height: shown.height,
                              child: Image.memory(_original!, fit: BoxFit.fill, gaplessPlayback: true),
                            ),
                            Positioned.fill(
                              child: CustomPaint(painter: _CropPainter([for (final c in _corners) toScreen(c)])),
                            ),
                            if (_magnifierAt != null)
                              Positioned(
                                left: _magnifierAt!.dx - 50,
                                top: _magnifierAt!.dy - 140,
                                child: const RawMagnifier(
                                  size: Size(100, 100),
                                  magnificationScale: 2.5,
                                  focalPointOffset: Offset(0, 90),
                                  decoration: MagnifierDecoration(
                                    shape: CircleBorder(side: BorderSide(color: Colors.white, width: 3)),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _apply,
                        child: _saving ? const Text('Straightening…') : const Text('Use these corners'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _CropPainter extends CustomPainter {
  final List<Offset> c;
  _CropPainter(this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addPolygon(c, true);
    canvas.drawPath(path, Paint()..color = Tokens.brandOrange.withValues(alpha: 0.15));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Tokens.brandOrange,
    );
    for (final p in c) {
      canvas.drawCircle(p, 16, Paint()..color = Colors.white);
      canvas.drawCircle(
        p,
        16,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Tokens.brandOrange,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => true;
}
