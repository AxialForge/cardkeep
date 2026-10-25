import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// The certificate a device shows when it hosts a sync: self-signed, made once
/// on this device, never shared. The pairing QR carries its sha256, so the other
/// device trusts this certificate and no other (S16.2, S16.3).
///
/// Pure Dart (basic_utils / pointycastle), so the same code makes the
/// certificate on Android and on Windows with no native library. A 2048-bit RSA
/// key takes a moment to make, so it is made once, in a separate isolate, and kept.
class DeviceCertificate {
  /// PEM text of the certificate and of its private key.
  final String certPem;
  final String keyPem;

  /// Lower-case hex sha256 of the certificate's DER bytes.
  final String fingerprint;

  const DeviceCertificate({required this.certPem, required this.keyPem, required this.fingerprint});

  /// Makes a new certificate. [days] of validity (default ten years: it is only a
  /// pin, nothing else checks it). [addresses] go in as subject alternative names.
  static Future<DeviceCertificate> generate({String name = 'CardKeep sync', int days = 3650}) {
    return Isolate.run(() => _generate(name, days));
  }

  static DeviceCertificate _generate(String name, int days) {
    final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final priv = pair.privateKey as RSAPrivateKey;
    final pub = pair.publicKey as RSAPublicKey;
    final csr = X509Utils.generateRsaCsrPem({'CN': name, 'O': 'CardKeep'}, priv, pub, san: ['localhost']);
    final cert = X509Utils.generateSelfSignedCertificate(priv, csr, days, sans: ['localhost']);
    return DeviceCertificate(
      certPem: cert,
      keyPem: CryptoUtils.encodeRSAPrivateKeyToPem(priv),
      fingerprint: fingerprintOfPem(cert),
    );
  }

  /// sha256 of the DER inside a PEM certificate.
  static String fingerprintOfPem(String certPem) => sha256.convert(derOfPem(certPem)).toString();

  static List<int> derOfPem(String pem) {
    final body = pem.split('\n').where((l) => l.isNotEmpty && !l.startsWith('-----')).join();
    return base64.decode(body.replaceAll('\r', ''));
  }

  /// A server context that presents this certificate.
  SecurityContext serverContext() {
    return SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(certPem))
      ..usePrivateKeyBytes(utf8.encode(keyPem));
  }

  Map<String, String> toJson() => {'cert': certPem, 'key': keyPem, 'fingerprint': fingerprint};

  static DeviceCertificate? fromJson(Map<String, Object?> j) {
    final c = j['cert'];
    final k = j['key'];
    if (c is! String || k is! String) return null;
    return DeviceCertificate(certPem: c, keyPem: k, fingerprint: fingerprintOfPem(c));
  }
}

/// Where the certificate and its key are kept: a file in the app's private
/// folder (not in the database, so a backup zip never carries the key).
class CertificateStore {
  final Directory dir;
  CertificateStore(this.dir);

  File get _file => File(p.join(dir.path, 'sync_certificate.json'));

  Future<DeviceCertificate> loadOrCreate() async {
    if (_file.existsSync()) {
      try {
        final c = DeviceCertificate.fromJson((jsonDecode(await _file.readAsString()) as Map).cast<String, Object?>());
        if (c != null) return c;
      } catch (_) {
        // damaged: make a new one; paired devices will need to pair again
      }
    }
    final c = await DeviceCertificate.generate();
    dir.createSync(recursive: true);
    await _file.writeAsString(jsonEncode(c.toJson()), flush: true);
    return c;
  }

  /// Forgets the certificate (Delete everything): the next host makes a new one.
  Future<void> delete() async {
    if (_file.existsSync()) await _file.delete();
  }
}
