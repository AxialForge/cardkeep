import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:card_organizer/app/theme.dart';
import 'package:card_organizer/core/platform/platform_info.dart';
import 'package:card_organizer/core/update/updater.dart';
import 'package:card_organizer/core/update/windows_updater.dart';
import 'package:card_organizer/features/settings/update_sheet.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

const _base = 'https://github.com/AxialForge/cardkeep/releases/download/v0.9.0';
const _zipName = 'CardKeep-0.9.0-windows-x64.zip';

void main() {
  late Directory root, install;
  late List<(String, List<String>)> launched;
  late List<bool> quit;

  setUp(() async {
    AppPalette.current = AppPalette.light;
    PlatformInfo.override = AppPlatform.windows;
    PackageInfo.setMockInitialValues(
      appName: 'CardKeep',
      packageName: 'com.axialforge.cardkeep',
      version: '0.8.0',
      buildNumber: '1',
      buildSignature: '',
    );
    root = await Directory.systemTemp.createTemp('ck_winsheet');
    install = await Directory(p.join(root.path, 'CardKeep')).create();
    await File(p.join(install.path, 'CardKeep.exe')).writeAsString('old');
    launched = [];
    quit = [];
    WindowsUpdater.instance = WindowsUpdater(
      installDir: install,
      workDir: Directory(p.join(root.path, 'work')),
      processId: 7,
      launch: (exe, args) async => launched.add((exe, args)),
      quit: () => quit.add(true),
    );
  });

  tearDown(() async {
    PlatformInfo.override = null;
    WindowsUpdater.instance = WindowsUpdater();
    Updater.client = http.Client();
    // The test's own cleanup must not race the sheet's file work.
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  void serve({required List<int> zip, String? sumsFor}) {
    final sums = '${sumsFor ?? sha256.convert(zip)}  $_zipName\n';
    Updater.client = MockClient((req) async {
      if (req.url.host == 'api.github.com') {
        return http.Response(
          jsonEncode([
            {
              'tag_name': 'v0.9.0',
              'name': '0.9.0',
              'body': '- **Windows updater**',
              'assets': [
                {'name': _zipName, 'size': zip.length, 'browser_download_url': '$_base/$_zipName'},
                {'name': 'SHA256SUMS-windows.txt', 'size': 90, 'browser_download_url': '$_base/SHA256SUMS-windows.txt'},
              ],
            },
          ]),
          200,
        );
      }
      if (req.url.path.endsWith('.txt')) return http.Response(sums, 200);
      return http.Response.bytes(zip, 200);
    });
  }

  List<int> goodZip() {
    final a = Archive();
    for (final n in ['CardKeep.exe', 'flutter_windows.dll', 'update.ps1']) {
      a.addFile(ArchiveFile.bytes(n, utf8.encode(n)));
    }
    return ZipEncoder().encode(a);
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(onPressed: () => showUpdateSheet(c), child: const Text('open')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 500)); // the sheet slides up
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// The sheet's file work runs on the real event loop, so give it real time between pumps,
  /// until [done] (or 8 seconds).
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 80 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.pump();
  }

  testWidgets('finds the newer version, downloads, unpacks, starts the helper and closes', (tester) async {
    serve(zip: goodZip());
    await open(tester);
    expect(find.text('CardKeep 0.9.0 is available (you have 0.8.0).'), findsOneWidget);
    expect(find.textContaining('closes and opens again'), findsOneWidget);
    expect(find.textContaining('Android'), findsNothing);

    await tester.tap(find.text('Download and install'));
    await settle(tester, () => quit.isNotEmpty);

    expect(launched, hasLength(1));
    expect(launched.single.$1, 'powershell.exe');
    expect(launched.single.$2, contains('-InstallDir'));
    expect(quit, [true]);
    expect(File(p.join('${install.path}.new', 'CardKeep.exe')).existsSync(), isTrue);
    // Nothing in the installed folder has changed: the helper does that after CardKeep closes.
    expect(File(p.join(install.path, 'CardKeep.exe')).readAsStringSync(), 'old');
  });

  testWidgets('a download that fails its checksum is reported and nothing is started', (tester) async {
    serve(zip: goodZip(), sumsFor: '0' * 64);
    await open(tester);
    await tester.tap(find.text('Download and install'));
    await settle(tester, () => find.text('Try again').evaluate().isNotEmpty);

    expect(find.textContaining('damaged'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(launched, isEmpty);
    expect(quit, isEmpty);
    expect(Directory('${install.path}.new').existsSync(), isFalse);
  });

  testWidgets('a copy that cannot update itself says why before downloading anything', (tester) async {
    final desktop = Directory(p.join(root.path, 'Desktop'))..createSync();
    WindowsUpdater.instance = WindowsUpdater(
      installDir: desktop,
      workDir: Directory(p.join(root.path, 'work')),
      requireExe: false,
      launch: (exe, args) async => launched.add((exe, args)),
      quit: () => quit.add(true),
    );
    var downloads = 0;
    final inner = goodZip();
    serve(zip: inner);
    final api = Updater.client;
    Updater.client = MockClient((req) async {
      if (req.url.host != 'api.github.com') downloads++;
      return api.get(req.url);
    });
    await open(tester);
    await tester.tap(find.text('Download and install'));
    await settle(tester, () => find.textContaining('folder of its own').evaluate().isNotEmpty);

    expect(find.textContaining('folder of its own'), findsOneWidget);
    expect(downloads, 0);
    expect(quit, isEmpty);
  });

  testWidgets('already on the latest version', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'CardKeep',
      packageName: 'com.axialforge.cardkeep',
      version: '0.9.0',
      buildNumber: '1',
      buildSignature: '',
    );
    serve(zip: goodZip());
    await open(tester);
    expect(find.text('CardKeep 0.9.0 is the latest version.'), findsOneWidget);
    expect(find.text('Download and install'), findsNothing);
  });
}
