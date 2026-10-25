import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../db/database.dart';
import 'pairing.dart';

/// The bearer tokens a host gave paired devices. Only the sha256 of each secret
/// is kept (in app_settings, per device), so a copy of the database cannot be
/// used to sign in. A token reads `<deviceId>.<secret>`, so the device is found
/// without searching.
class SessionStore {
  final AppDatabase db;
  final Random _random;
  SessionStore(this.db, {Random? random}) : _random = random ?? Random.secure();

  static String _key(String peerId) => 'sync.session.$peerId';

  static String _hash(String secret) => sha256.convert(utf8.encode(secret)).toString();

  /// A new token for [peerId]; any earlier one stops working.
  Future<String> create(String peerId) async {
    final secret = randomToken(_random, 32);
    await db.customStatement('INSERT OR REPLACE INTO app_settings (key, value) VALUES (?, ?)', [
      _key(peerId),
      _hash(secret),
    ]);
    return '$peerId.$secret';
  }

  /// The device a token belongs to, or null when it is wrong or was revoked.
  Future<String?> verify(String? bearer) async {
    if (bearer == null) return null;
    final dot = bearer.indexOf('.');
    if (dot <= 0 || dot == bearer.length - 1) return null;
    final peerId = bearer.substring(0, dot);
    final secret = bearer.substring(dot + 1);
    final r = await db
        .customSelect('SELECT value FROM app_settings WHERE key = ?', variables: [Variable.withString(_key(peerId))])
        .getSingleOrNull();
    if (r == null) return null;
    return _constantTimeEquals(r.read<String>('value'), _hash(secret)) ? peerId : null;
  }

  Future<void> remove(String peerId) => db.customStatement('DELETE FROM app_settings WHERE key = ?', [_key(peerId)]);

  /// Forgets every token (Delete everything).
  Future<void> removeAll() => db.customStatement("DELETE FROM app_settings WHERE key LIKE 'sync.session.%'");

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// What this device needs to reach the host it paired with.
class HostCredentials {
  final String hostId;
  final String hostName;
  final String host;
  final int port;

  /// sha256 of the host's certificate, from the pairing QR.
  final String fingerprint;

  /// The bearer token the host gave us.
  final String session;

  const HostCredentials({
    required this.hostId,
    required this.hostName,
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.session,
  });

  HostCredentials withAddress(String host, int port) => HostCredentials(
    hostId: hostId,
    hostName: hostName,
    host: host,
    port: port,
    fingerprint: fingerprint,
    session: session,
  );

  Map<String, Object?> toJson() => {
    'host_id': hostId,
    'host_name': hostName,
    'host': host,
    'port': port,
    'fingerprint': fingerprint,
    'session': session,
  };

  factory HostCredentials.fromJson(Map<String, Object?> j) => HostCredentials(
    hostId: j['host_id'] as String,
    hostName: j['host_name'] as String,
    host: j['host'] as String,
    port: j['port'] as int,
    fingerprint: j['fingerprint'] as String,
    session: j['session'] as String,
  );
}

/// Where the client keeps the host it paired with.
abstract interface class HostCredentialStore {
  Future<HostCredentials?> load();
  Future<void> save(HostCredentials c);
  Future<void> clear();
}

/// Keeps the host in app_settings of the local database.
class DbHostCredentialStore implements HostCredentialStore {
  final AppDatabase db;
  DbHostCredentialStore(this.db);

  static const _key = 'sync.host';

  @override
  Future<HostCredentials?> load() async {
    final r = await db
        .customSelect('SELECT value FROM app_settings WHERE key = ?', variables: [Variable.withString(_key)])
        .getSingleOrNull();
    if (r == null) return null;
    try {
      return HostCredentials.fromJson((jsonDecode(r.read<String>('value')) as Map).cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(HostCredentials c) => db.customStatement(
    'INSERT OR REPLACE INTO app_settings (key, value) VALUES (?, ?)',
    [_key, jsonEncode(c.toJson())],
  );

  @override
  Future<void> clear() => db.customStatement('DELETE FROM app_settings WHERE key = ?', [_key]);
}
