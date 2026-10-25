import 'package:path/path.dart' as p;

/// What dropping files on the Windows window should do (S16.11).
enum DropKind { vcard, csv, image, backup, ignored }

class DropItem {
  final String path;
  final DropKind kind;
  const DropItem(this.path, this.kind);
}

const imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.bmp', '.heic'};

/// Sorts a dropped file by its extension. Folders and unknown files are ignored.
DropKind classifyDrop(String path) {
  final ext = p.extension(path).toLowerCase();
  if (ext == '.vcf') return DropKind.vcard;
  if (ext == '.csv') return DropKind.csv;
  if (ext == '.zip') return DropKind.backup;
  if (imageExtensions.contains(ext)) return DropKind.image;
  return DropKind.ignored;
}

/// The files of one drop, sorted. Order is kept; ignored files stay in the list
/// so the screen can say how many it skipped.
List<DropItem> classifyDrops(Iterable<String> paths) => [for (final f in paths) DropItem(f, classifyDrop(f))];

/// A one-line summary such as "2 contact files, 5 card photos (1 skipped)".
String describeDrop(List<DropItem> items) {
  int n(DropKind k) => items.where((i) => i.kind == k).length;
  String part(int count, String one, String many) => count == 0 ? '' : '$count ${count == 1 ? one : many}';
  final parts = [
    part(n(DropKind.vcard), 'contact file', 'contact files'),
    part(n(DropKind.csv), 'spreadsheet', 'spreadsheets'),
    part(n(DropKind.image), 'card photo', 'card photos'),
    part(n(DropKind.backup), 'backup', 'backups'),
  ].where((s) => s.isNotEmpty).join(', ');
  final skipped = n(DropKind.ignored);
  if (parts.isEmpty) {
    return skipped == 0 ? 'Nothing was dropped.' : 'CardKeep cannot use ${skipped == 1 ? 'that file' : 'those files'}.';
  }
  return skipped == 0 ? parts : '$parts ($skipped skipped)';
}
