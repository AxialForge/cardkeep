import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:card_organizer/core/update/updater.dart';
import 'package:card_organizer/core/update/windows_updater.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

const _base = 'https://github.com/AxialForge/cardkeep/releases/download/v0.9.0';
const _zipName = 'CardKeep-0.9.0-windows-x64.zip';

Map<String, Object?> _asset(String name, {int size = 10, String? digest}) => {
  'name': name,
  'size': size,
  'browser_download_url': '$_base/$name',
  'digest': ?digest,
};

Uint8List _zip(Map<String, String> files) {
  final a = Archive();
  files.forEach((name, text) => a.addFile(ArchiveFile.bytes(name, utf8.encode(text))));
  return Uint8List.fromList(ZipEncoder().encode(a));
}

final _goodFiles = {'CardKeep.exe': 'exe', 'flutter_windows.dll': 'dll', 'update.ps1': '# helper', 'data/app.so': 'so'};

String _sha(List<int> b) => sha256.convert(b).toString();

void main() {
  late Directory root, install, work;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ck_winupd');
    install = await Directory(p.join(root.path, 'CardKeep')).create();
    await File(p.join(install.path, 'CardKeep.exe')).writeAsString('old exe');
    await File(p.join(install.path, 'update.ps1')).writeAsString('# old helper');
    work = Directory(p.join(root.path, 'work'));
  });
  tearDown(() async {
    Updater.client = http.Client();
    await root.delete(recursive: true);
  });

  WindowsUpdater make({
    List<(String, List<String>)>? launched,
    List<bool>? quit,
    bool requireExe = true,
    Directory? installDir,
  }) => WindowsUpdater(
    installDir: installDir ?? install,
    workDir: work,
    processId: 4242,
    launch: (exe, args) async => launched?.add((exe, args)),
    quit: () => quit?.add(true),
    requireExe: requireExe,
  );

  group('finding the files in a release', () {
    test('picks the Windows zip and the checksum file, not the phone files', () {
      final r = WindowsUpdater.pickAssets([
        _asset('CardKeep-0.9.0-arm64-v8a.apk'),
        _asset('SHA256SUMS.txt'),
        _asset(_zipName),
        _asset('SHA256SUMS-windows.txt'),
      ]);
      expect(r.file!['name'], _zipName);
      expect(r.sums!['name'], 'SHA256SUMS-windows.txt');
    });

    test('a release without them gives nothing', () {
      final r = WindowsUpdater.pickAssets([_asset('CardKeep-0.9.0-arm64-v8a.apk'), _asset('SHA256SUMS.txt')]);
      expect(r.file, isNull);
      expect(r.sums, isNull);
    });

    test('check compares versions and finds the zip and its sums', () async {
      Updater.client = MockClient(
        (_) async => http.Response(
          jsonEncode([
            {
              'tag_name': 'v0.9.0',
              'body': 'Windows updater',
              'assets': [_asset(_zipName, size: 99), _asset('SHA256SUMS-windows.txt')],
            },
          ]),
          200,
        ),
      );
      final newer = await make().check(currentVersion: '0.8.0');
      expect(newer.available, isTrue);
      expect(newer.latest, '0.9.0');
      expect(newer.assetName, _zipName);
      expect(newer.assetBytes, 99);
      expect(newer.sumsUrl, '$_base/SHA256SUMS-windows.txt');
      expect(newer.canInstall, isTrue);

      expect((await make().check(currentVersion: '0.9.0')).available, isFalse);
      expect((await make().check(currentVersion: '0.10.0')).available, isFalse);
    });

    test('the phone check still ignores the Windows files', () async {
      Updater.client = MockClient(
        (_) async => http.Response(
          jsonEncode([
            {
              'tag_name': 'v0.9.0',
              'assets': [_asset(_zipName), _asset('CardKeep-0.9.0-arm64-v8a.apk')],
            },
          ]),
          200,
        ),
      );
      final i = await Updater.check(currentVersion: '0.8.0', abis: ['arm64-v8a']);
      expect(i.assetName, 'CardKeep-0.9.0-arm64-v8a.apk');
      expect(i.sumsUrl, isNull);
    });
  });

  group('the checksum file', () {
    final h = 'a' * 64;
    final h2 = 'B' * 64;

    test('reads sha256sum and Get-FileHash lines, case-insensitively, with CRLF', () {
      final text = '$h  $_zipName\r\n$h2 *other.zip\r\n';
      expect(WindowsUpdater.parseSums(text, _zipName), h);
      expect(WindowsUpdater.parseSums(text, 'OTHER.zip'), 'b' * 64);
      expect(WindowsUpdater.parseSums(text, 'missing.zip'), isNull);
      expect(WindowsUpdater.parseSums('not a hash  $_zipName', _zipName), isNull);
      expect(WindowsUpdater.parseSums('', _zipName), isNull);
    });

    UpdateInfo info({String? sums = '$_base/SHA256SUMS-windows.txt', String? digest}) => UpdateInfo(
      current: '0.8.0',
      latest: '0.9.0',
      notes: const [],
      assetName: _zipName,
      assetUrl: '$_base/$_zipName',
      sha256: digest,
      sumsUrl: sums,
    );

    test('gives the hash from the sums file', () async {
      Updater.client = MockClient((_) async => http.Response('$h  $_zipName\n', 200));
      expect(await make().expectedSha(info()), h);
      expect(await make().expectedSha(info(digest: h)), h);
    });

    test('refuses when GitHub\'s own digest disagrees', () async {
      Updater.client = MockClient((_) async => http.Response('$h  $_zipName\n', 200));
      await expectLater(
        make().expectedSha(info(digest: 'c' * 64)),
        throwsA(isA<UpdateException>().having((e) => e.message, 'm', contains('disagree'))),
      );
    });

    test('refuses with no sums file, a sums file for another name, or a foreign host', () async {
      Updater.client = MockClient((_) async => http.Response('$h  other.zip\n', 200));
      await expectLater(make().expectedSha(info(sums: null)), throwsA(isA<UpdateException>()));
      await expectLater(
        make().expectedSha(info()),
        throwsA(isA<UpdateException>().having((e) => e.message, 'm', contains('does not list'))),
      );
      await expectLater(make().expectedSha(info(sums: 'https://evil.example/s.txt')), throwsA(isA<UpdateException>()));
      await expectLater(make().expectedSha(info(sums: 'http://github.com/s.txt')), throwsA(isA<UpdateException>()));
    });

    test('offline or an error page is a plain message', () async {
      Updater.client = MockClient((_) async => throw const SocketException('offline'));
      await expectLater(
        make().expectedSha(info()),
        throwsA(isA<UpdateException>().having((e) => e.message, 'm', contains('internet'))),
      );
      Updater.client = MockClient((_) async => http.Response('nope', 404));
      await expectLater(make().expectedSha(info()), throwsA(isA<UpdateException>()));
    });
  });

  group('download', () {
    test('keeps a zip that matches its sums, throws away one that does not', () async {
      final zip = _zip(_goodFiles);
      final good = _sha(zip);
      var sums = '$good  $_zipName\n';
      Updater.client = MockClient((req) async {
        if (req.url.path.endsWith('.txt')) return http.Response(sums, 200);
        return http.Response.bytes(zip, 200);
      });
      final info = UpdateInfo(
        current: '0.8.0',
        latest: '0.9.0',
        notes: const [],
        assetName: _zipName,
        assetUrl: '$_base/$_zipName',
        assetBytes: zip.length,
        sumsUrl: '$_base/SHA256SUMS-windows.txt',
      );
      final seen = <double>[];
      final f = await make().download(info, seen.add);
      expect(f.path, p.join(work.path, _zipName));
      expect(await f.readAsBytes(), zip);
      expect(seen.last, 1.0);

      sums = '${'0' * 64}  $_zipName\n';
      await expectLater(
        make().download(info, (_) {}),
        throwsA(isA<UpdateException>().having((e) => e.message, 'm', contains('damaged'))),
      );
      expect(File(p.join(work.path, _zipName)).existsSync(), isFalse);
    });

    test('a file bigger than the limit is not downloaded', () async {
      Updater.client = MockClient((_) async => http.Response('${'a' * 64}  $_zipName\n', 200));
      const info = UpdateInfo(
        current: '0.8.0',
        latest: '0.9.0',
        notes: [],
        assetName: _zipName,
        assetUrl: '$_base/$_zipName',
        assetBytes: WindowsUpdater.maxZipBytes + 1,
        sumsUrl: '$_base/SHA256SUMS-windows.txt',
      );
      await expectLater(
        make().download(info, (_) {}),
        throwsA(isA<UpdateException>().having((e) => e.message, 'm', contains('large'))),
      );
    });
  });

  group('staging', () {
    Future<File> zipFile(Map<String, String> files) async {
      await work.create(recursive: true);
      return File(p.join(work.path, 'u.zip'))..writeAsBytesSync(_zip(files));
    }

    test('unpacks beside the install folder, including sub-folders', () async {
      final staging = await make().stage(await zipFile(_goodFiles));
      expect(staging.path, '${install.path}.new');
      expect(File(p.join(staging.path, 'CardKeep.exe')).readAsStringSync(), 'exe');
      expect(File(p.join(staging.path, 'data', 'app.so')).readAsStringSync(), 'so');
      // The installed folder is untouched until the helper runs.
      expect(File(p.join(install.path, 'CardKeep.exe')).readAsStringSync(), 'old exe');
    });

    test('replaces a staging folder left by an earlier try', () async {
      final stale = await Directory('${install.path}.new').create();
      await File(p.join(stale.path, 'old.txt')).writeAsString('x');
      await make().stage(await zipFile(_goodFiles));
      expect(File(p.join(stale.path, 'old.txt')).existsSync(), isFalse);
    });

    test('reads names written with backslashes', () async {
      final staging = await make().stage(await zipFile({..._goodFiles, 'data\\flutter_assets\\x.bin': 'bin'}));
      expect(File(p.join(staging.path, 'data', 'flutter_assets', 'x.bin')).readAsStringSync(), 'bin');
    });

    test('refuses paths that climb out, and leaves nothing behind', () async {
      for (final evil in ['../evil.txt', 'a/../../evil.txt', '..\\evil.txt', '/abs.txt', 'C:/x.txt']) {
        await expectLater(
          make().stage(await zipFile({..._goodFiles, evil: 'x'})),
          throwsA(isA<UpdateException>().having((e) => e.message, 'm', contains('unsafe'))),
          reason: evil,
        );
        expect(Directory('${install.path}.new').existsSync(), isFalse, reason: evil);
        expect(File(p.join(root.path, 'evil.txt')).existsSync(), isFalse, reason: evil);
      }
    });

    test('refuses a zip that is not CardKeep or not a zip', () async {
      for (final missing in ['CardKeep.exe', 'flutter_windows.dll', 'update.ps1']) {
        final files = {..._goodFiles}..remove(missing);
        await expectLater(
          make().stage(await zipFile(files)),
          throwsA(isA<UpdateException>().having((e) => e.message, 'm', contains(missing))),
        );
        expect(Directory('${install.path}.new').existsSync(), isFalse);
      }
      await work.create(recursive: true);
      final junk = File(p.join(work.path, 'junk.zip'))..writeAsBytesSync([1, 2, 3, 4]);
      await expectLater(make().stage(junk), throwsA(isA<UpdateException>()));
    });
  });

  group('can this copy update itself', () {
    test('a folder of its own that can be written beside', () {
      expect(make(requireExe: false).installProblem(), isNull);
      expect(make().installProblem(), isNull); // has CardKeep.exe
    });

    test('not when the exe is missing, or CardKeep sits loose on the Desktop or Downloads', () async {
      final empty = await Directory(p.join(root.path, 'Empty')).create();
      expect(make(installDir: empty).installProblem(), contains('find its own'));
      for (final name in ['Desktop', 'Downloads', 'Documents']) {
        final d = await Directory(p.join(root.path, name)).create();
        expect(make(installDir: d, requireExe: false).installProblem(), contains('folder of its own'), reason: name);
      }
    });

    test('not when the folder beside it cannot be written', () {
      final gone = Directory(p.join(root.path, 'no', 'such', 'place', 'CardKeep'));
      expect(make(installDir: gone, requireExe: false).installProblem(), contains('cannot change'));
    });
  });

  group('handing over to the helper', () {
    test('builds the PowerShell command line', () {
      final u = make();
      final args = u.helperArguments(r'C:\Temp\update.ps1');
      expect(args.sublist(0, 7), [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
      ]);
      expect(args[7], r'C:\Temp\update.ps1');
      Object? after(String flag) => args[args.indexOf(flag) + 1];
      expect(after('-ProcessId'), '4242');
      expect(after('-InstallDir'), install.path);
      expect(after('-StagingDir'), '${install.path}.new');
      expect(after('-ExeName'), 'CardKeep.exe');
      expect(after('-LogFile'), p.join(work.path, 'update.log'));
      expect(after('-RolledBackMarker'), p.join(work.path, 'rolled-back.txt'));
    });

    test('a trailing slash on the install folder does not leak into the paths', () {
      final u = make(installDir: Directory('${install.path}${Platform.pathSeparator}'));
      expect(u.stagingDir.path, '${install.path}.new');
      expect(u.oldDir.path, '${install.path}.old');
    });

    test('copies the newest helper out of the install folder, starts it and quits', () async {
      final launched = <(String, List<String>)>[];
      final quit = <bool>[];
      final u = make(launched: launched, quit: quit);
      final staging = await u.stage(
        await (() async {
          await work.create(recursive: true);
          return File(p.join(work.path, 'u.zip'))..writeAsBytesSync(_zip(_goodFiles));
        })(),
      );
      await u.applyAndQuit(staging);
      expect(File(p.join(work.path, 'update.ps1')).readAsStringSync(), '# helper'); // the staged, newer one
      expect(launched, hasLength(1));
      expect(launched.single.$1, 'powershell.exe');
      expect(launched.single.$2, contains(p.join(work.path, 'update.ps1')));
      expect(quit, [true]);
    });

    test('falls back to the installed helper, and refuses with none', () async {
      final staging = await Directory('${install.path}.new').create();
      final launched = <(String, List<String>)>[];
      final quit = <bool>[];
      final u = make(launched: launched, quit: quit);
      await u.applyAndQuit(staging);
      expect(File(p.join(work.path, 'update.ps1')).readAsStringSync(), '# old helper');
      expect(quit, [true]);

      File(p.join(install.path, 'update.ps1')).deleteSync();
      await expectLater(u.applyAndQuit(staging), throwsA(isA<UpdateException>()));
      expect(quit, hasLength(1)); // did not quit the second time
    });

    test('does not quit when the helper cannot be started', () async {
      final staging = await Directory('${install.path}.new').create();
      final quit = <bool>[];
      final u = WindowsUpdater(
        installDir: install,
        workDir: work,
        processId: 1,
        launch: (_, _) async => throw const ProcessException('powershell.exe', []),
        quit: () => quit.add(true),
      );
      await expectLater(u.applyAndQuit(staging), throwsA(isA<UpdateException>()));
      expect(quit, isEmpty);
    });
  });

  group('after the update', () {
    test('a rolled-back marker is reported once', () async {
      final u = make();
      expect(await u.rolledBackLastTime(), isFalse);
      await work.create(recursive: true);
      await u.rolledBackMarker.writeAsString('2026-10-25T10:00:00');
      expect(await u.rolledBackLastTime(), isTrue);
      expect(await u.rolledBackLastTime(), isFalse);
    });

    test('clean-up removes .old, .failed, .new, the zip and the helper copy, not the install', () async {
      final u = make();
      for (final d in [u.oldDir, u.failedDir, u.stagingDir]) {
        await File(p.join(d.path, 'x.txt')).create(recursive: true);
      }
      await work.create(recursive: true);
      await File(p.join(work.path, _zipName)).writeAsString('z');
      await File(p.join(work.path, 'update.ps1')).writeAsString('s');
      await File(p.join(work.path, 'update.log')).writeAsString('log');

      await u.cleanUp();
      expect(u.oldDir.existsSync(), isFalse);
      expect(u.failedDir.existsSync(), isFalse);
      expect(u.stagingDir.existsSync(), isFalse);
      expect(File(p.join(work.path, _zipName)).existsSync(), isFalse);
      expect(File(p.join(work.path, 'update.ps1')).existsSync(), isFalse);
      expect(File(p.join(work.path, 'update.log')).existsSync(), isTrue); // kept for troubleshooting
      expect(File(p.join(install.path, 'CardKeep.exe')).existsSync(), isTrue);
    });

    test('clean-up with nothing to clean is quiet', () async {
      await make().cleanUp();
    });
  });
}
