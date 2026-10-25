import 'dart:convert';
import 'dart:math';

import '../change_set.dart';
import 'wire.dart';

const _qrPrefix = 'cardkeep-sync:';

/// What the pairing QR holds (S16.2): where the phone is, the one-time token,
/// the sha256 of its certificate, and its name. The PC scans or pastes it, then
/// trusts that certificate and no other.
class PairingPayload {
  final String host;
  final int port;
  final String token;
  final String certSha256;
  final String deviceName;
  final int version;

  const PairingPayload({
    required this.host,
    required this.port,
    required this.token,
    required this.certSha256,
    required this.deviceName,
    this.version = syncProtocolVersion,
  });

  Map<String, Object?> toJson() => {
    'host': host,
    'port': port,
    'token': token,
    'cert_sha256': certSha256,
    'device_name': deviceName,
    'v': version,
  };

  /// The text in the QR code: a prefix and the JSON, URL-safe base64.
  String toQrText() => '$_qrPrefix${base64Url.encode(utf8.encode(jsonEncode(toJson())))}';

  factory PairingPayload.fromJson(Map<String, Object?> j) {
    final host = j['host'];
    final port = j['port'];
    final token = j['token'];
    final cert = j['cert_sha256'];
    final name = j['device_name'];
    final v = j['v'];
    if (host is! String || port is! int || token is! String || cert is! String || name is! String || v is! int) {
      throw const SyncFormatException('That is not a CardKeep pairing code.');
    }
    if (v > syncProtocolVersion) {
      throw const SyncFormatException('That pairing code is from a newer CardKeep. Update CardKeep first.');
    }
    if (cert.length != 64) throw const SyncFormatException('That pairing code is damaged.');
    return PairingPayload(host: host, port: port, token: token, certSha256: cert, deviceName: name, version: v);
  }

  /// Reads the text of a scanned or pasted QR. Throws [SyncFormatException].
  static PairingPayload parse(String text) {
    final t = text.trim();
    if (!t.startsWith(_qrPrefix)) throw const SyncFormatException('That is not a CardKeep pairing code.');
    try {
      final json = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(t.substring(_qrPrefix.length)))));
      if (json is! Map) throw const SyncFormatException('That pairing code is damaged.');
      return PairingPayload.fromJson(json.cast<String, Object?>());
    } on FormatException {
      throw const SyncFormatException('That pairing code is damaged.');
    }
  }
}

/// The one-time pairing tokens a host has handed out: each lives for [ttl] and
/// works once (S16.2).
class PairingTokens {
  final Duration ttl;
  final DateTime Function() clock;
  final Random _random;
  final Map<String, DateTime> _live = {};

  PairingTokens({this.ttl = const Duration(minutes: 2), DateTime Function()? clock, Random? random})
    : clock = clock ?? DateTime.now,
      _random = random ?? Random.secure();

  /// A new token; any older unused token stops working (one QR at a time).
  String issue() {
    _live.clear();
    final token = randomToken(_random, 16);
    _live[token] = clock().add(ttl);
    return token;
  }

  /// When the current token stops working, or null when there is none.
  DateTime? get expiresAt => _live.values.isEmpty ? null : _live.values.first;

  /// True once for a live token; false for a wrong, used or expired one.
  bool consume(String token) {
    final expires = _live.remove(token);
    return expires != null && clock().isBefore(expires);
  }

  void clear() => _live.clear();
}

/// [bytes] random bytes as URL-safe text without padding.
String randomToken(Random random, int bytes) =>
    base64Url.encode([for (var i = 0; i < bytes; i++) random.nextInt(256)]).replaceAll('=', '');
