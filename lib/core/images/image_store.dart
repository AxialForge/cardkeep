import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Card images on disk, named by the sha256 of the rectified JPEG (spec §3: the
/// database stores hashes only). Callers pass JPEGs already re-encoded without
/// EXIF (see `processStill`), so GPS and camera data never reach the store.
///
/// Layout under [root]: `original/HASH.jpg` (q90), `rectified/HASH.jpg` (q85),
/// `thumb/HASH.jpg` (400 px long edge), `pending/` for captures not yet processed.
class ImageStore {
  final Directory root;
  ImageStore(this.root);

  File original(String hash) => File(p.join(root.path, 'original', '$hash.jpg'));
  File rectified(String hash) => File(p.join(root.path, 'rectified', '$hash.jpg'));
  File thumb(String hash) => File(p.join(root.path, 'thumb', '$hash.jpg'));

  /// Logos cut from cards (256 px squares), named by their own hash.
  File logo(String hash) => File(p.join(root.path, 'logo', '$hash.jpg'));

  Future<String> saveLogo(Uint8List jpeg) async {
    final hash = hashOf(jpeg);
    await _write(logo(hash), jpeg);
    return hash;
  }

  static String hashOf(Uint8List rectifiedJpeg) => sha256.convert(rectifiedJpeg).toString();

  /// Writes the untouched capture before any processing, so a crash never
  /// loses a card. [commit] deletes it once the card is stored.
  Future<File> savePending(Uint8List bytes) async {
    final dir = Directory(p.join(root.path, 'pending'))..createSync(recursive: true);
    final f = File(p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}.jpg'));
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  /// Stores one card and returns its hash. Idempotent: the same rectified
  /// image stored twice keeps one copy.
  Future<String> commit({
    required Uint8List originalJpeg,
    required Uint8List rectifiedJpeg,
    required Uint8List thumbJpeg,
    File? pending,
  }) async {
    final hash = hashOf(rectifiedJpeg);
    await _write(rectified(hash), rectifiedJpeg);
    await _write(original(hash), originalJpeg);
    await _write(thumb(hash), thumbJpeg);
    if (pending != null && pending.existsSync()) await pending.delete();
    return hash;
  }

  /// Captures left in `pending/` by a crash; the scanner offers to process them.
  List<File> orphanedPending() {
    final dir = Directory(p.join(root.path, 'pending'));
    if (!dir.existsSync()) return const [];
    return dir.listSync().whereType<File>().toList();
  }

  bool has(String hash) => rectified(hash).existsSync();

  Future<void> delete(String hash) async {
    for (final f in [original(hash), rectified(hash), thumb(hash)]) {
      if (f.existsSync()) await f.delete();
    }
  }

  static Future<void> _write(File f, List<int> bytes) async {
    if (f.existsSync()) return;
    f.parent.createSync(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
  }
}
