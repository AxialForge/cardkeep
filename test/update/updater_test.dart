import 'dart:convert';
import 'dart:io';

import 'package:card_organizer/core/update/updater.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> asset(String name, {int size = 10, String? digest}) => {
  'name': name,
  'size': size,
  'browser_download_url': 'https://github.com/AxialForge/cardkeep/releases/download/x/$name',
  'digest': ?digest,
};

void main() {
  test('compareVersions', () {
    expect(compareVersions('0.1.1', '0.1.0'), 1);
    expect(compareVersions('v0.2.0', '0.10.0'), -1);
    expect(compareVersions('1.0.0+5', '1.0.0'), 0);
    expect(compareVersions('1.0.0-rc1', '1.0.0'), -1);
  });

  test('picks the APK for the phone CPU from CardKeep release names', () {
    final assets = [
      asset('CardKeep-0.2.0-arm64-v8a.apk'),
      asset('CardKeep-0.2.0-armeabi-v7a.apk'),
      asset('CardKeep-0.2.0-x86_64.apk'),
    ];
    expect(Updater.pickAsset(assets, ['arm64-v8a', 'armeabi-v7a'])!['name'], 'CardKeep-0.2.0-arm64-v8a.apk');
    expect(Updater.pickAsset(assets, ['armeabi-v7a'])!['name'], 'CardKeep-0.2.0-armeabi-v7a.apk');
    expect(Updater.pickAsset(assets, ['x86_64'])!['name'], 'CardKeep-0.2.0-x86_64.apk');
    expect(Updater.pickAsset([asset('notes.txt')], ['arm64-v8a']), isNull);
  });

  test('check lists newer releases, skips drafts and pre-releases', () async {
    Updater.client = MockClient(
      (req) async => http.Response(
        jsonEncode([
          {'tag_name': 'v0.1.0', 'name': '0.1.0', 'body': 'first', 'assets': []},
          {'tag_name': 'v0.3.0-rc1', 'prerelease': true, 'assets': []},
          {
            'tag_name': 'v0.2.0',
            'name': 'Release 0.2.0',
            'body': '## Added\n- **Scanner**',
            'published_at': '2026-10-20T10:00:00Z',
            'assets': [asset('CardKeep-0.2.0-arm64-v8a.apk', size: 1234)],
          },
          {'tag_name': 'v0.1.1', 'name': '0.1.1', 'body': 'themes', 'assets': []},
          {'tag_name': 'v9.9.9', 'draft': true, 'assets': []},
        ]),
        200,
      ),
    );
    final i = await Updater.check(currentVersion: '0.1.0', abis: ['arm64-v8a']);
    expect(i.available, isTrue);
    expect(i.latest, '0.2.0');
    expect(i.notes.map((n) => n.version), ['0.2.0', '0.1.1']);
    expect(i.assetName, 'CardKeep-0.2.0-arm64-v8a.apk');
    expect(i.assetBytes, 1234);
  });

  test('up to date, offline and rate limit give plain answers', () async {
    Updater.client = MockClient((_) async => http.Response(jsonEncode([{'tag_name': 'v0.1.1', 'assets': []}]), 200));
    expect((await Updater.check(currentVersion: '0.1.1', abis: const [])).available, isFalse);

    Updater.client = MockClient((_) async => throw const SocketException('offline'));
    expect(
      () => Updater.check(currentVersion: '0.1.1', abis: const []),
      throwsA(isA<UpdateException>().having((e) => e.message, 'message', contains('internet'))),
    );

    Updater.client = MockClient((_) async => http.Response('', 403));
    expect(
      () => Updater.check(currentVersion: '0.1.1', abis: const []),
      throwsA(isA<UpdateException>().having((e) => e.message, 'message', contains('Too many'))),
    );
  });

  test('download verifies SHA-256 and refuses non-GitHub hosts', () async {
    final body = utf8.encode('fake apk bytes');
    final good = sha256.convert(body).toString();
    Updater.client = MockClient((_) async => http.Response.bytes(body, 200));
    final dir = await Directory.systemTemp.createTemp('ck_upd');
    addTearDown(() => dir.delete(recursive: true));

    UpdateInfo info(String url, String digest) => UpdateInfo(
      current: '0.1.0',
      latest: '0.2.0',
      notes: const [],
      assetUrl: url,
      sha256: digest,
      assetBytes: body.length,
    );
    const url = 'https://github.com/AxialForge/cardkeep/releases/download/v0.2.0/CardKeep-0.2.0-arm64-v8a.apk';

    final f = await Updater.download(info(url, good), (_) {}, to: File('${dir.path}/a.apk'));
    expect(await f.readAsBytes(), body);

    expect(
      () => Updater.download(info(url, 'deadbeef'), (_) {}, to: File('${dir.path}/b.apk')),
      throwsA(isA<UpdateException>().having((e) => e.message, 'message', contains('damaged'))),
    );
    expect(
      () => Updater.download(info('https://evil.example/x.apk', good), (_) {}, to: File('${dir.path}/c.apk')),
      throwsA(isA<UpdateException>().having((e) => e.message, 'message', contains('safe'))),
    );
  });
}
