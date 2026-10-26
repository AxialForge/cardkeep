import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'updater.dart';

/// Updates the Windows app from CardKeep's GitHub Releases (S16.13).
///
/// The release carries `CardKeep-<ver>-windows-x64.zip` and `SHA256SUMS-windows.txt`.
/// The zip is downloaded, checked against the sums file (and GitHub's own digest, when
/// it lists one), unpacked beside the installed folder as `<install>.new`, and a small
/// PowerShell helper (update.ps1, bundled in the zip) swaps the folders after CardKeep
/// has closed: `<install>` becomes `<install>.old`, `<install>.new` becomes `<install>`,
/// and the new CardKeep is started. If it stops within seconds the helper puts the old
/// folder back. The new CardKeep removes `.old` once it has been running a while.
/// Contacts live in Documents, not in the install folder, so they are never touched.
class WindowsUpdater {
  static const exeName = 'CardKeep.exe';
  static const sumsName = 'SHA256SUMS-windows.txt';
  static const helperName = 'update.ps1';
  static const zipSuffix = '-windows-x64.zip';

  /// The unpacked app is about 100 MB; anything far past that is not ours.
  static const maxZipBytes = 300 * 1024 * 1024;
  static const maxUnpackedBytes = 800 * 1024 * 1024;
  static const maxEntries = 2000;

  /// How long the new version must run before the old folder is thrown away.
  static const settleAfter = Duration(seconds: 30);

  /// Tests replace this; the app uses the real one.
  static WindowsUpdater instance = WindowsUpdater();

  final Directory installDir;
  final Directory workDir;
  final int processId;
  final Future<void> Function(String exe, List<String> args) launch;
  final void Function() quit;

  /// Tests turn this off so an install folder needs no real exe.
  final bool requireExe;

  WindowsUpdater({
    Directory? installDir,
    Directory? workDir,
    int? processId,
    Future<void> Function(String exe, List<String> args)? launch,
    void Function()? quit,
    this.requireExe = true,
  }) : installDir = installDir ?? Directory(p.dirname(Platform.resolvedExecutable)),
       workDir = workDir ?? Directory(p.join(Directory.systemTemp.path, 'cardkeep-update')),
       processId = processId ?? pid,
       launch = launch ?? _launchDetached,
       quit = quit ?? _quit;

  static Future<void> _launchDetached(String exe, List<String> args) async {
    await Process.start(exe, args, mode: ProcessStartMode.detached);
  }

  static void _quit() => exit(0);

  Directory get stagingDir => Directory('${_trim(installDir.path)}.new');
  Directory get oldDir => Directory('${_trim(installDir.path)}.old');
  Directory get failedDir => Directory('${_trim(installDir.path)}.failed');
  File get logFile => File(p.join(workDir.path, 'update.log'));

  /// Written by the helper when the new version would not start and the old one came back.
  File get rolledBackMarker => File(p.join(workDir.path, 'rolled-back.txt'));

  static String _trim(String path) => path.replaceFirst(RegExp(r'[\\/]+$'), '');

  // ------------------------------------------------------------------ check

  /// The zip and the checksum file in a release's assets.
  static ({Map<String, Object?>? file, Map<String, Object?>? sums}) pickAssets(List<dynamic> assets) {
    Map<String, Object?>? file, sums;
    for (final a in assets) {
      if (a is! Map<String, Object?>) continue;
      final name = '${a['name']}'.toLowerCase();
      if (name.startsWith('cardkeep-') && name.endsWith(zipSuffix)) file ??= a;
      if (name == sumsName.toLowerCase()) sums ??= a;
    }
    return (file: file, sums: sums);
  }

  Future<UpdateInfo> check({String? currentVersion}) =>
      Updater.check(currentVersion: currentVersion, pickAsset: pickAssets);

  // --------------------------------------------------------------- checksum

  /// The hash `sha256sum` / Get-FileHash printed for [fileName]: `<64 hex>  <name>` (a `*`
  /// before the name marks binary mode).
  static String? parseSums(String text, String fileName) {
    for (final line in const LineSplitter().convert(text)) {
      final m = RegExp(r'^\s*([0-9a-fA-F]{64})\s+\*?(.+?)\s*$').firstMatch(line);
      if (m != null && m[2]!.toLowerCase() == fileName.toLowerCase()) return m[1]!.toLowerCase();
    }
    return null;
  }

  /// The SHA-256 the zip must have: the sums file's, and GitHub's digest must agree when
  /// it lists one. Without a sums file there is nothing to check against, so no update.
  Future<String> expectedSha(UpdateInfo info) async {
    final name = info.assetName ?? '';
    final uri = Uri.tryParse(info.sumsUrl ?? '');
    if (uri == null || !Updater.isTrustedDownload(uri)) {
      throw UpdateException('This release has no checksum file, so CardKeep did not download it.');
    }
    final String text;
    try {
      final r = await Updater.client
          .get(uri, headers: {'User-Agent': 'CardKeep-updater'})
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200 || r.bodyBytes.length > 64 * 1024) throw const FormatException();
      text = utf8.decode(r.bodyBytes);
    } catch (_) {
      throw UpdateException('Could not get the update checksum. Check your internet connection and try again.');
    }
    final sha = parseSums(text, name);
    if (sha == null) throw UpdateException('The update checksum does not list this file, so it was not downloaded.');
    final github = info.sha256;
    if (github != null && github != sha) {
      throw UpdateException('The update checksums disagree, so CardKeep did not download it.');
    }
    return sha;
  }

  // --------------------------------------------------------------- download

  /// Why this copy cannot update itself, or null when it can.
  String? installProblem() {
    final dir = installDir;
    final name = p.basename(_trim(dir.path)).toLowerCase();
    if (p.dirname(_trim(dir.path)) == _trim(dir.path) || const {'desktop', 'documents', 'downloads'}.contains(name)) {
      return 'CardKeep is not in its own folder. Unzip the download into a folder of its own '
          '(for example CardKeep) and run it from there.';
    }
    if (requireExe && !File(p.join(dir.path, exeName)).existsSync()) {
      return 'CardKeep could not find its own folder.';
    }
    try {
      final probe = Directory(p.join(p.dirname(_trim(dir.path)), '.cardkeep-write-test'))..createSync();
      probe.deleteSync();
    } catch (_) {
      return 'CardKeep cannot change the folder it is in (${p.dirname(_trim(dir.path))}). Move the CardKeep '
          'folder somewhere you can write to, such as Documents or the Desktop.';
    }
    return null;
  }

  /// Downloads the zip into [workDir], checks size and SHA-256, returns the file.
  Future<File> download(UpdateInfo info, void Function(double) onProgress) async {
    final sha = await expectedSha(info);
    await workDir.create(recursive: true);
    final safeName = p.basename(info.assetName ?? 'CardKeep-update$zipSuffix');
    return Updater.download(
      info,
      onProgress,
      to: File(p.join(workDir.path, safeName)),
      maxBytes: maxZipBytes,
      expectedSha256: sha,
    );
  }

  // ------------------------------------------------------------------ stage

  /// Unpacks [zip] into [stagingDir], refusing paths that climb out of it, and checks the
  /// result looks like CardKeep. The old staging folder, if any, is replaced.
  Future<Directory> stage(File zip) async {
    final dir = stagingDir;
    if (dir.existsSync()) await dir.delete(recursive: true);
    try {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
      } catch (_) {
        throw UpdateException('The downloaded update is not a valid zip file.');
      }
      if (archive.files.length > maxEntries) {
        throw UpdateException('The update has too many files, so it was not used.');
      }
      var unpacked = 0;
      for (final f in archive.files) {
        if (f.isFile) unpacked += f.size;
      }
      if (unpacked > maxUnpackedBytes) throw UpdateException('The update is unexpectedly large, so it was not used.');
      await dir.create(recursive: true);
      for (final f in archive.files) {
        if (!f.isFile) continue;
        final name = f.name.replaceAll('\\', '/');
        if (name.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(name)) {
          throw UpdateException('The update has an unsafe file path, so it was not used.');
        }
        final out = File(p.normalize(p.join(dir.path, name)));
        if (!p.isWithin(dir.path, out.path)) {
          throw UpdateException('The update has an unsafe file path, so it was not used.');
        }
        await out.parent.create(recursive: true);
        await out.writeAsBytes(f.content as List<int>, flush: true);
      }
      for (final must in [exeName, 'flutter_windows.dll', helperName]) {
        if (!File(p.join(dir.path, must)).existsSync()) {
          throw UpdateException('The update is missing $must, so it was not used.');
        }
      }
      return dir;
    } catch (_) {
      if (dir.existsSync()) await dir.delete(recursive: true);
      rethrow;
    }
  }

  // ------------------------------------------------------------------ apply

  /// The command line for the helper: PowerShell runs [script] with these named values.
  List<String> helperArguments(String script, {Directory? staging}) => [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-WindowStyle',
    'Hidden',
    '-File',
    script,
    '-ProcessId',
    '$processId',
    '-InstallDir',
    _trim(installDir.path),
    '-StagingDir',
    _trim((staging ?? stagingDir).path),
    '-ExeName',
    exeName,
    '-LogFile',
    logFile.path,
    '-RolledBackMarker',
    rolledBackMarker.path,
  ];

  /// Copies the helper out of the way of the folder swap, starts it, and closes CardKeep.
  /// The staged copy of the helper is preferred (it is the newest); the installed one is
  /// the fallback.
  Future<void> applyAndQuit(Directory staging) async {
    await workDir.create(recursive: true);
    final staged = File(p.join(staging.path, helperName));
    final installed = File(p.join(installDir.path, helperName));
    final source = staged.existsSync() ? staged : installed;
    if (!source.existsSync()) throw UpdateException('The update helper is missing, so CardKeep cannot restart itself.');
    final script = File(p.join(workDir.path, helperName));
    await source.copy(script.path);
    if (rolledBackMarker.existsSync()) await rolledBackMarker.delete();
    try {
      await launch('powershell.exe', helperArguments(script.path, staging: staging));
    } catch (_) {
      throw UpdateException('Could not start the update helper. The update was not applied.');
    }
    quit();
  }

  // ------------------------------------------------------------ housekeeping

  /// Run when the app opens. Returns true when the last update was rolled back (the new
  /// version would not start), so the app can say so. Leftover folders from an update are
  /// removed after the app has run for [settleAfter].
  Future<bool> rolledBackLastTime() async {
    try {
      if (!rolledBackMarker.existsSync()) return false;
      await rolledBackMarker.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The new version has been running for a while: the previous folder, a failed one and
  /// the download are no longer needed. Never throws.
  Future<void> cleanUp() async {
    for (final d in [oldDir, failedDir, stagingDir]) {
      try {
        if (d.existsSync()) await d.delete(recursive: true);
      } catch (_) {}
    }
    try {
      for (final f in workDir.existsSync() ? workDir.listSync() : const <FileSystemEntity>[]) {
        if (f is File && (f.path.endsWith('.zip') || f.path.endsWith(helperName))) await f.delete();
      }
    } catch (_) {}
  }
}
