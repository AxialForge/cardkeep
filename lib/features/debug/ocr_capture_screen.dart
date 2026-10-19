import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../parser/ocr_adapter_mlkit.dart';
import '../../parser/rules.dart';

/// Debug tool for the OCR test set (spec §12). Picks card photos, runs ML Kit,
/// and writes `<id>.jpg`, `<id>.ocr.json` and a `<id>.draft.json` ground-truth
/// draft (parser output, to be corrected by hand and renamed `<id>.json`).
///
/// Output folder: Android/data/com.axialforge.card_organizer/files/ocr_capture
/// (reachable over USB in File Explorer, or `adb pull`).
class OcrCaptureScreen extends StatefulWidget {
  const OcrCaptureScreen({super.key});

  @override
  State<OcrCaptureScreen> createState() => _OcrCaptureScreenState();
}

class _OcrCaptureScreenState extends State<OcrCaptureScreen> {
  final _ocr = MlKitOcrAdapter();
  final _log = <String>[];
  Directory? _out;
  bool _busy = false;
  String _region = 'US';

  @override
  void initState() {
    super.initState();
    _initDir();
  }

  Future<void> _initDir() async {
    final base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'ocr_capture'))..createSync(recursive: true);
    setState(() => _out = dir);
  }

  @override
  void dispose() {
    _ocr.close();
    super.dispose();
  }

  int _nextNumber() {
    final nums = _out!
        .listSync()
        .map((f) => RegExp(r'c(\d{3})').firstMatch(p.basename(f.path))?.group(1))
        .whereType<String>()
        .map(int.parse);
    return nums.isEmpty ? 1 : nums.reduce((a, b) => a > b ? a : b) + 1;
  }

  Future<void> _pick({required bool camera}) async {
    final picker = ImagePicker();
    final files = camera
        ? [?await picker.pickImage(source: ImageSource.camera)]
        : await picker.pickMultiImage();
    if (files.isEmpty) return;
    setState(() => _busy = true);
    var n = _nextNumber();
    for (final f in files) {
      final id = 'c${n.toString().padLeft(3, '0')}';
      try {
        final page = await _ocr.recognize(f.path);
        await File(f.path).copy(p.join(_out!.path, '$id.jpg'));
        const enc = JsonEncoder.withIndent('  ');
        await File(p.join(_out!.path, '$id.ocr.json')).writeAsString(enc.convert(page.toJson()));
        final fields = parseCard(page, region: _region).toFields()
          ..removeWhere((_, v) => v == null);
        await File(p.join(_out!.path, '$id.draft.json')).writeAsString(enc.convert({
          'region': _region,
          'kind': 'plain',
          'source': p.basename(f.path),
          'fields': fields,
        }));
        _log.insert(0, '$id  ${page.lines.length} lines  ${fields['name'] ?? '(no name)'}');
        n++;
      } catch (e) {
        _log.insert(0, 'FAILED ${p.basename(f.path)}: $e');
      }
      if (mounted) setState(() {});
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OCR capture (debug)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(_out?.path ?? '…', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(children: [
              const Text('Phone region '),
              DropdownButton<String>(
                value: _region,
                items: [for (final r in ['US', 'CA', 'GB', 'DE', 'FR', 'MX']) DropdownMenuItem(value: r, child: Text(r))],
                onChanged: _busy ? null : (v) => setState(() => _region = v!),
              ),
            ]),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || _out == null ? null : () => _pick(camera: false),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Pick photos'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy || _out == null ? null : () => _pick(camera: true),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Take photo'),
            ),
            if (_busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
            const Divider(height: 32),
            Expanded(
              child: ListView(children: [for (final l in _log) Text(l, style: const TextStyle(fontFamily: 'monospace'))]),
            ),
          ],
        ),
      ),
    );
  }
}
