import 'package:flutter/material.dart';

import 'features/debug/ocr_capture_screen.dart';

void main() => runApp(const CardOrganizerApp());

class CardOrganizerApp extends StatelessWidget {
  const CardOrganizerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Card Organizer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E1A2B)),
        scaffoldBackgroundColor: const Color(0xFFF3F4F6),
      ),
      // Until the Contacts screen exists (build step 3), the app opens on the
      // OCR capture tool used to build the test set.
      home: const OcrCaptureScreen(),
    );
  }
}
