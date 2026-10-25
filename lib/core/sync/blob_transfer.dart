import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Card images travel by sha256, only the ones the other device lacks, in
/// chunks that can be resumed after the link drops (S16.7). These are the two
/// ends of that: where a blob is read from and where it is written to.
abstract interface class BlobSource {
  /// Size in bytes, or null when this device does not have the blob.
  Future<int?> size(String sha256);

  /// [length] bytes starting at [offset] (fewer at the end).
  Future<Uint8List> read(String sha256, int offset, int length);
}

abstract interface class BlobSink {
  /// True when the finished blob is here.
  Future<bool> has(String sha256);

  /// Bytes of an unfinished blob received so far (0 when none).
  Future<int> received(String sha256);

  /// Writes [bytes] at [offset], which must equal [received]; any other offset
  /// is refused so a repeated or out-of-order chunk can never corrupt a blob.
  Future<void> write(String sha256, int offset, Uint8List bytes);

  /// Checks the received bytes against [sha256] and, if they match, keeps the
  /// blob. A mismatch throws the partial data away and returns false.
  Future<bool> commit(String sha256);
}

/// The hashes in [hashes] that [sink] does not have yet, in order, once each.
Future<List<String>> missingBlobs(BlobSink sink, Iterable<String> hashes) async {
  final missing = <String>[];
  final seen = <String>{};
  for (final h in hashes) {
    if (!seen.add(h)) continue;
    if (!await sink.has(h)) missing.add(h);
  }
  return missing;
}

/// Copies one blob from [from] to [to], resuming where [to] stopped. Stops early
/// after [maxChunks] chunks (a dropped link in tests); returns true once the blob
/// is complete and its hash matches.
Future<bool> transferBlob(
  BlobSource from,
  BlobSink to,
  String sha256, {
  int chunkSize = 64 * 1024,
  int? maxChunks,
}) async {
  if (await to.has(sha256)) return true;
  final total = await from.size(sha256);
  if (total == null) return false;
  var offset = await to.received(sha256);
  var chunks = 0;
  while (offset < total) {
    if (maxChunks != null && chunks >= maxChunks) return false;
    final bytes = await from.read(sha256, offset, chunkSize);
    if (bytes.isEmpty) return false;
    await to.write(sha256, offset, bytes);
    offset += bytes.length;
    chunks++;
  }
  return to.commit(sha256);
}

/// Blobs in memory: the test double, and a fine store for small sets.
class MemoryBlobStore implements BlobSource, BlobSink {
  final Map<String, Uint8List> _done = {};
  final Map<String, BytesBuilder> _partial = {};

  /// Adds a finished blob and returns its sha256.
  String put(Uint8List bytes) {
    final h = sha256.convert(bytes).toString();
    _done[h] = bytes;
    return h;
  }

  Uint8List? get(String sha) => _done[sha];
  int get count => _done.length;

  @override
  Future<int?> size(String sha256) async => _done[sha256]?.length;

  @override
  Future<Uint8List> read(String sha256, int offset, int length) async {
    final b = _done[sha256];
    if (b == null || offset >= b.length) return Uint8List(0);
    final end = offset + length > b.length ? b.length : offset + length;
    return Uint8List.sublistView(b, offset, end);
  }

  @override
  Future<bool> has(String sha256) async => _done.containsKey(sha256);

  @override
  Future<int> received(String sha256) async => _partial[sha256]?.length ?? 0;

  @override
  Future<void> write(String sha256, int offset, Uint8List bytes) async {
    final have = _partial[sha256]?.length ?? 0;
    if (offset != have) throw StateError('Expected offset $have, got $offset');
    (_partial[sha256] ??= BytesBuilder(copy: false)).add(bytes);
  }

  @override
  Future<bool> commit(String sha256Hex) async {
    final b = _partial.remove(sha256Hex);
    if (b == null) return false;
    final bytes = b.takeBytes();
    if (sha256.convert(bytes).toString() != sha256Hex) return false;
    _done[sha256Hex] = bytes;
    return true;
  }
}
