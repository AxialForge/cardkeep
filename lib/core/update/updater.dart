import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as hash;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Compares "1.2.3" versions. A leading "v" and a "+build" suffix are ignored;
/// "-rc1" sorts just below the same number without it.
int compareVersions(String a, String b) {
  (List<BigInt>, bool) parse(String v) {
    final noBuild = v.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
    final dash = noBuild.indexOf('-');
    final core = dash < 0 ? noBuild : noBuild.substring(0, dash);
    final parts = core.split('.').map((p) => BigInt.tryParse(p) ?? BigInt.zero).toList();
    while (parts.length < 3) {
      parts.add(BigInt.zero);
    }
    return (parts, dash >= 0);
  }

  final (x, xPre) = parse(a);
  final (y, yPre) = parse(b);
  for (var i = 0; i < x.length && i < y.length; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]).sign;
  }
  if (x.length != y.length) return x.length.compareTo(y.length);
  if (xPre != yPre) return xPre ? -1 : 1;
  return 0;
}

class ReleaseNote {
  final String version, title, body;
  final DateTime? date;
  const ReleaseNote(this.version, this.title, this.body, this.date);
}

class UpdateInfo {
  final String current, latest;
  final List<ReleaseNote> notes; // releases newer than the installed one, newest first
  final String? assetName, assetUrl, sha256;
  final int? assetBytes;
  const UpdateInfo({
    required this.current,
    required this.latest,
    required this.notes,
    this.assetName,
    this.assetUrl,
    this.sha256,
    this.assetBytes,
  });

  bool get available => compareVersions(latest, current) > 0;
  bool get canInstall => assetUrl != null;
}

class UpdateException implements Exception {
  final String message;
  UpdateException(this.message);
  @override
  String toString() => message;
}

/// Checks CardKeep's GitHub Releases and installs the matching APK. This is
/// the app's only internet use besides features you switch on yourself, and it
/// only runs when you tap "Check for updates" or turn on checking at startup.
/// The APK is signed with the same key as the installed app, so Android
/// upgrades in place and keeps your data.
class Updater {
  static const repo = 'AxialForge/cardkeep';
  static http.Client client = http.Client();

  /// The APK for this phone's CPU. Release files are named
  /// `CardKeep-X.Y.Z-ABI.apk` (arm64-v8a, armeabi-v7a, x86_64).
  static Map<String, Object?>? pickAsset(List<dynamic> assets, List<String> abis) {
    final apks = [
      for (final a in assets)
        if (a is Map<String, Object?> && '${a['name']}'.toLowerCase().endsWith('.apk')) a,
    ];
    for (final abi in abis) {
      final hit = apks.where((a) => '${a['name']}'.toLowerCase().contains(abi.toLowerCase())).firstOrNull;
      if (hit != null) return hit;
    }
    return apks.length == 1 ? apks.first : null;
  }

  static Future<List<String>> _abis() async {
    try {
      return (await DeviceInfoPlugin().androidInfo).supportedAbis;
    } catch (_) {
      return const ['arm64-v8a'];
    }
  }

  static Future<UpdateInfo> check({String? currentVersion, List<String>? abis}) async {
    final current = currentVersion ?? (await PackageInfo.fromPlatform()).version;
    final http.Response r;
    try {
      r = await client
          .get(
            Uri.https('api.github.com', '/repos/$repo/releases', {'per_page': '20'}),
            headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'CardKeep-updater'},
          )
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      throw UpdateException('Could not check for updates. Check your internet connection.');
    }
    if (r.statusCode == 404) throw UpdateException('No updates were found.');
    if (r.statusCode == 403 || r.statusCode == 429) {
      throw UpdateException('Too many update checks. Please try again later.');
    }
    if (r.statusCode != 200) throw UpdateException('The update check had a problem. Please try again later.');

    final list = jsonDecode(utf8.decode(r.bodyBytes));
    final releases = [
      for (final x in (list is List ? list : const []))
        if (x is Map<String, Object?> &&
            x['draft'] != true &&
            x['prerelease'] != true &&
            x['tag_name'] is String &&
            (x['tag_name'] as String).isNotEmpty)
          x,
    ]..sort((a, b) => compareVersions('${b['tag_name']}', '${a['tag_name']}'));
    if (releases.isEmpty) return UpdateInfo(current: current, latest: current, notes: const []);

    final top = releases.first;
    final asset = pickAsset(top['assets'] is List ? top['assets']! as List : const [], abis ?? await _abis());
    final digest = asset?['digest'];
    String bare(Object? tag) => '$tag'.replaceFirst(RegExp(r'^[vV]'), '');
    return UpdateInfo(
      current: current,
      latest: bare(top['tag_name']),
      notes: [
        for (final x in releases.where((x) => compareVersions('${x['tag_name']}', current) > 0))
          ReleaseNote(
            bare(x['tag_name']),
            '${x['name'] ?? x['tag_name']}',
            '${x['body'] ?? ''}'.trim(),
            DateTime.tryParse('${x['published_at']}'),
          ),
      ],
      assetName: asset?['name'] as String?,
      assetUrl: asset?['browser_download_url'] as String?,
      sha256: digest is String && digest.startsWith('sha256:') ? digest.substring(7).toLowerCase() : null,
      assetBytes: asset?['size'] is int ? asset!['size']! as int : null,
    );
  }

  /// Downloads with progress, then checks the size and (when GitHub lists it) the SHA-256.
  static Future<File> download(UpdateInfo info, void Function(double) onProgress, {File? to}) async {
    final uri = Uri.tryParse(info.assetUrl ?? '');
    const hosts = {'github.com', 'objects.githubusercontent.com', 'github-releases.githubusercontent.com'};
    if (uri == null || uri.scheme != 'https' || !hosts.contains(uri.host)) {
      throw UpdateException('This update does not look safe to download, so CardKeep skipped it.');
    }
    if (info.sha256 == null && info.assetBytes == null) {
      throw UpdateException('CardKeep could not check this update file, so it was not downloaded.');
    }
    final file = to ?? File('${(await getTemporaryDirectory()).path}/cardkeep-update.apk');
    if (await file.exists()) await file.delete();
    final req = http.Request('GET', uri)..headers['User-Agent'] = 'CardKeep-updater';
    final resp = await client.send(req).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) throw UpdateException('The download did not work. Please try again.');
    final total = resp.contentLength ?? info.assetBytes ?? 0;
    final sink = file.openWrite();
    var got = 0;
    try {
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress((got / total).clamp(0.0, 1.0));
      }
    } finally {
      await sink.close();
    }
    if (info.assetBytes != null && got != info.assetBytes) {
      await file.delete();
      throw UpdateException('The download did not finish. Please try again.');
    }
    if (info.sha256 != null) {
      final digest = (await hash.sha256.bind(file.openRead()).first).toString();
      if (digest != info.sha256) {
        await file.delete();
        throw UpdateException('The downloaded update was damaged, so it was thrown away. Please try again.');
      }
    }
    return file;
  }

  /// Hands the APK to Android's installer. The first time, Android asks you to
  /// allow installs from CardKeep.
  static Future<void> install(File apk) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw UpdateException('Installing updates is Android-only.');
    }
    final r = await OpenFilex.open(apk.path, type: 'application/vnd.android.package-archive');
    if (r.type == ResultType.permissionDenied) {
      throw UpdateException('Allow CardKeep to install apps (Android will ask), then tap Install again.');
    }
    if (r.type != ResultType.done) throw UpdateException('Could not start the installer. Please try again.');
  }
}
