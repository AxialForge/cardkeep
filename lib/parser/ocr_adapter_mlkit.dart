import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr.dart';

/// On-device ML Kit OCR (Android/iOS only). Kept out of parser imports so
/// the parser stays pure Dart.
class MlKitOcrAdapter implements OcrAdapter {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  Future<OcrPage> recognize(String imagePath) async {
    final result = await _recognizer.processImage(InputImage.fromFilePath(imagePath));
    return OcrPage([
      for (final block in result.blocks)
        for (final line in block.lines)
          OcrLine(
            line.text,
            left: line.boundingBox.left,
            top: line.boundingBox.top,
            width: line.boundingBox.width,
            height: line.boundingBox.height,
            confidence: line.confidence,
            angle: line.angle,
          ),
    ]);
  }

  Future<void> close() => _recognizer.close();
}
