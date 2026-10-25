import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../core/transfer/csv_import.dart';
import '../../scan/scan_worker.dart';
import 'drop_classifier.dart';

/// The card photos in [paths] (jpg, png...), in order.
List<String> imagePaths(Iterable<String> paths) => [
  for (final f in paths)
    if (classifyDrop(f) == DropKind.image) f,
];

/// Puts card photos in the Review queue. This PC cannot read the text on them
/// (the reader is on the phone), so each arrives as a photo to fill in by hand.
/// Returns how many were added.
Future<int> addCardPhotos(WidgetRef ref, Iterable<String> paths) async {
  var n = 0;
  for (final f in imagePaths(paths)) {
    try {
      final bytes = await File(f).readAsBytes();
      await ref.read(scanWorkerProvider.notifier).add(ScanJob(Uint8List.fromList(bytes)));
      n++;
    } on FileSystemException {
      // unreadable file: skip it, the count says how many went in
    }
  }
  return n;
}

/// The image files directly inside [dir], sorted by name.
List<String> imagesInFolder(Directory dir) {
  final files = <String>[
    for (final e in dir.listSync(followLinks: false))
      if (e is File && classifyDrop(e.path) == DropKind.image) e.path,
  ]..sort((a, b) => p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase()));
  return files;
}

/// "Import card images from a folder" (S16.12): pick a folder, add its photos.
/// Returns a line for the user, or null if they cancelled.
Future<String?> importCardFolder(WidgetRef ref) async {
  final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Choose a folder of card photos');
  if (dir == null) return null;
  final found = imagesInFolder(Directory(dir));
  if (found.isEmpty) return 'No card photos (jpg, png) in that folder.';
  final n = await addCardPhotos(ref, found);
  return _addedLine(n);
}

String _addedLine(int n) => n == 0
    ? 'Could not read those photos.'
    : '$n card photo${n == 1 ? '' : 's'} added to the Review queue. Type each card in by hand: reading card text is a phone feature.';

/// What happens when files are dropped on the window: one contact file or
/// spreadsheet opens its import; card photos go to the queue. Returns a line to show.
Future<String> handleDroppedFiles(WidgetRef ref, GoRouter router, List<String> paths) async {
  final items = classifyDrops(paths);
  final summary = describeDrop(items);
  final vcf = items.where((i) => i.kind == DropKind.vcard).firstOrNull;
  if (vcf != null) {
    unawaited(router.push('/import', extra: Uint8List.fromList(await File(vcf.path).readAsBytes())));
    return summary;
  }
  final csv = items.where((i) => i.kind == DropKind.csv).firstOrNull;
  if (csv != null) {
    final text = utf8.decode(await File(csv.path).readAsBytes(), allowMalformed: true);
    unawaited(router.push('/import', extra: parseCsv(text, keepBlank: true)));
    return summary;
  }
  final photos = items.where((i) => i.kind == DropKind.image).map((i) => i.path).toList();
  if (photos.isNotEmpty) return _addedLine(await addCardPhotos(ref, photos));
  if (items.any((i) => i.kind == DropKind.backup)) {
    unawaited(router.push('/import'));
    return 'To restore a backup, choose CardKeep backup on this page.';
  }
  return summary;
}
