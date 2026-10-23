import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import 'scan_pipeline.dart';

/// On-device QR reading with ML Kit (Android, iOS).
class MlKitQrReader implements QrReader {
  final _scanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);

  @override
  Future<List<String>> read(String imagePath) async {
    final codes = await _scanner.processImage(InputImage.fromFilePath(imagePath));
    return [
      for (final c in codes)
        if (c.rawValue case final v? when v.trim().isNotEmpty) v,
    ];
  }

  @override
  Future<List<(String, QrBox?)>> readWithBoxes(String imagePath) async {
    final codes = await _scanner.processImage(InputImage.fromFilePath(imagePath));
    return [
      for (final c in codes)
        if (c.rawValue case final v? when v.trim().isNotEmpty)
          (v, (c.boundingBox.left, c.boundingBox.top, c.boundingBox.width, c.boundingBox.height)),
    ];
  }

  Future<void> close() => _scanner.close();
}
