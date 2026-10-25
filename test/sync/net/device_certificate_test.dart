import 'dart:io';

import 'package:card_organizer/core/sync/net/device_certificate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a generated certificate loads into a secure server and has a stable fingerprint', () async {
    final sw = Stopwatch()..start();
    final c = await DeviceCertificate.generate();
    // ignore: avoid_print
    print('certificate made in ${sw.elapsedMilliseconds} ms');
    expect(c.fingerprint, hasLength(64));
    expect(DeviceCertificate.fingerprintOfPem(c.certPem), c.fingerprint);
    final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, c.serverContext());
    addTearDown(() => server.close(force: true));
    expect(server.port, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the store keeps one certificate between runs', () async {
    final dir = await Directory.systemTemp.createTemp('ck_cert');
    addTearDown(() => dir.delete(recursive: true));
    final a = await CertificateStore(dir).loadOrCreate();
    final b = await CertificateStore(dir).loadOrCreate();
    expect(b.fingerprint, a.fingerprint);
    await CertificateStore(dir).delete();
    final c = await CertificateStore(dir).loadOrCreate();
    expect(c.fingerprint, isNot(a.fingerprint));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
