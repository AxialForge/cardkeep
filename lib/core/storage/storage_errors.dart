import 'dart:io';

/// True when [e] means the phone has run out of room (S15.3): a file write that
/// failed with ENOSPC, or SQLite reporting a full disk.
bool isStorageFull(Object e) {
  if (e is FileSystemException) {
    final code = e.osError?.errorCode;
    if (code == 28 || code == 112) return true; // ENOSPC (Android/Linux), ERROR_DISK_FULL (Windows)
  }
  final text = '$e'.toLowerCase();
  return text.contains('no space left') ||
      text.contains('disk is full') ||
      text.contains('database or disk is full') ||
      text.contains('not enough space');
}

/// The one friendly sentence shown when something could not be saved for lack of room.
const storageFullHelp =
    'The phone is out of storage. Free some space (delete old photos or apps), then try again. Nothing already in CardKeep was lost.';
