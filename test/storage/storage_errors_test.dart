import 'dart:io';

import 'package:card_organizer/core/storage/storage_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a failed write with ENOSPC or a full disk counts as storage full', () {
    expect(
      isStorageFull(const FileSystemException('write failed', '/x', OSError('No space left on device', 28))),
      isTrue,
    );
    expect(isStorageFull(const FileSystemException('write failed', 'C:/x', OSError('disk full', 112))), isTrue);
    expect(isStorageFull(Exception('SqliteException(13): database or disk is full')), isTrue);
  });

  test('other errors do not', () {
    expect(isStorageFull(const FileSystemException('denied', '/x', OSError('Permission denied', 13))), isFalse);
    expect(isStorageFull(StateError('nope')), isFalse);
  });

  test('the help text says what to do and that nothing was lost', () {
    expect(storageFullHelp, contains('Free some space'));
    expect(storageFullHelp, contains('Nothing already in CardKeep was lost'));
  });
}
