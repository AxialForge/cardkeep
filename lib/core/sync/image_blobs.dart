import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../images/image_store.dart';
import 'blob_transfer.dart';
import 'net/sync_server.dart' show KindAwareBlobSink;
import 'net/wire.dart';

/// Makes a 400 px thumbnail from a card's JPEG. Null means "could not": the
/// card image itself is then used as its thumbnail.
typedef ThumbMaker = Uint8List? Function(Uint8List jpeg);

Uint8List? thumbnailWithImagePackage(Uint8List jpeg) {
  try {
    final src = img.decodeJpg(jpeg);
    if (src == null) return null;
    final long = src.width > src.height ? src.width : src.height;
    if (long <= 400) return jpeg;
    final scale = 400 / long;
    final small = img.copyResize(
      src,
      width: (src.width * scale).round(),
      height: (src.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
    return Uint8List.fromList(img.encodeJpg(small, quality: 80));
  } catch (_) {
    return null;
  }
}

/// The card images and logos of an [ImageStore] as sync blobs. A blob is named
/// by its sha256, which is also the file name, so reading is a lookup and a
/// received image is checked against its name before it is kept.
///
/// What travels is the finished (rectified) card and its logo. The untouched
/// capture stays on the phone that scanned it: the other device keeps the
/// rectified card in its place, so "Adjust corners" there works on that.
class ImageBlobStore implements BlobSource, BlobSink, KindAwareBlobSink {
  final ImageStore store;
  final ThumbMaker thumbMaker;
  final Map<String, String> _kinds = {};

  ImageBlobStore(this.store, {ThumbMaker? thumbMaker}) : thumbMaker = thumbMaker ?? thumbnailWithImagePackage;

  @override
  void expect(String sha256, String kind) => _kinds[sha256] = kind;

  File? _finished(String sha) {
    final rectified = store.rectified(sha);
    if (rectified.existsSync()) return rectified;
    final logo = store.logo(sha);
    if (logo.existsSync()) return logo;
    return null;
  }

  File _partial(String sha) => File(p.join(store.root.path, 'pending', 'sync', '$sha.part'));

  @override
  Future<int?> size(String sha256) async => _finished(sha256)?.lengthSync();

  @override
  Future<Uint8List> read(String sha256, int offset, int length) async {
    final f = _finished(sha256);
    if (f == null) return Uint8List(0);
    final raf = await f.open();
    try {
      final total = await raf.length();
      if (offset >= total) return Uint8List(0);
      await raf.setPosition(offset);
      return await raf.read(offset + length > total ? total - offset : length);
    } finally {
      await raf.close();
    }
  }

  @override
  Future<bool> has(String sha256) async => _finished(sha256) != null;

  @override
  Future<int> received(String sha256) async {
    final f = _partial(sha256);
    return f.existsSync() ? f.lengthSync() : 0;
  }

  @override
  Future<void> write(String sha256, int offset, Uint8List bytes) async {
    final f = _partial(sha256);
    final have = f.existsSync() ? f.lengthSync() : 0;
    if (offset != have) throw StateError('Expected offset $have, got $offset');
    f.parent.createSync(recursive: true);
    await f.writeAsBytes(bytes, mode: FileMode.append, flush: true);
  }

  @override
  Future<bool> commit(String sha256Hex) async {
    final f = _partial(sha256Hex);
    if (!f.existsSync()) return false;
    final bytes = await f.readAsBytes();
    await f.delete();
    if (sha256.convert(bytes).toString() != sha256Hex) return false;
    final kind = _kinds.remove(sha256Hex) ?? blobKindCard;
    if (kind == blobKindLogo) {
      await store.saveLogo(bytes);
    } else {
      final thumb = thumbMaker(bytes) ?? bytes;
      await store.commit(originalJpeg: bytes, rectifiedJpeg: bytes, thumbJpeg: thumb);
    }
    return true;
  }
}
