import 'dart:io';

import 'package:card_organizer/app/drawer.dart';
import 'package:card_organizer/core/platform/platform_info.dart';
import 'package:card_organizer/features/desktop/desktop_actions.dart';
import 'package:card_organizer/features/desktop/desktop_home.dart';
import 'package:card_organizer/features/desktop/desktop_intents.dart';
import 'package:card_organizer/features/desktop/drop_classifier.dart';
import 'package:card_organizer/features/desktop/window_bounds.dart';
import 'package:card_organizer/features/settings/settings_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => PlatformInfo.override = null);

  group('what the platform can do', () {
    test('Windows has no camera, NFC, reminders or phone lock, but updates itself', () {
      PlatformInfo.override = AppPlatform.windows;
      expect(PlatformInfo.isDesktop, isTrue);
      expect(PlatformInfo.canScan, isFalse);
      expect(PlatformInfo.canTap, isFalse);
      expect(PlatformInfo.hasPhoneLock, isFalse);
      expect(PlatformInfo.hasReminders, isFalse);
      expect(PlatformInfo.canSelfUpdate, isTrue);
    });

    test('Android keeps all of them', () {
      PlatformInfo.override = AppPlatform.android;
      expect(PlatformInfo.isDesktop, isFalse);
      expect(PlatformInfo.canScan, isTrue);
      expect(PlatformInfo.canTap, isTrue);
      expect(PlatformInfo.hasPhoneLock, isTrue);
      expect(PlatformInfo.hasReminders, isTrue);
      expect(PlatformInfo.canSelfUpdate, isTrue);
    });

    test('the drawer drops Scan and Tap on Windows and renames Sync', () {
      PlatformInfo.override = AppPlatform.windows;
      final labels = destinationsFor(mainDestinations).map((d) => d.label).toList();
      expect(labels, isNot(contains('Scan cards')));
      expect(labels, isNot(contains('Tap cards (NFC)')));
      expect(labels, contains('Sync with phone'));
      expect(labels, isNot(contains('Sync to desktop')));
      expect(labels, containsAll(['Contacts', 'Review queue', 'Import', 'Export and backup']));
      PlatformInfo.override = AppPlatform.android;
      final phone = destinationsFor(mainDestinations).map((d) => d.label).toList();
      expect(phone, containsAll(['Scan cards', 'Tap cards (NFC)', 'Sync to desktop']));
    });

    test('Settings hides what only a phone has', () {
      PlatformInfo.override = AppPlatform.windows;
      final win = visibleSettingsSections();
      expect(win, isNot(contains('Reminders')));
      expect(win, isNot(contains('Privacy')));
      expect(win, containsAll(['Appearance', 'Contacts', 'Backups', 'Data', 'Updates', 'Help', 'About']));
      PlatformInfo.override = AppPlatform.android;
      expect(visibleSettingsSections(), settingsSections);
    });
  });

  group('two panes', () {
    test('only a wide Windows window gets the list beside the contact', () {
      PlatformInfo.override = AppPlatform.windows;
      expect(useTwoPane(899), isFalse);
      expect(useTwoPane(900), isTrue);
      expect(useTwoPane(1600), isTrue);
      PlatformInfo.override = AppPlatform.android;
      expect(useTwoPane(1600), isFalse, reason: 'a tablet keeps the phone layout');
    });
  });

  group('keyboard shortcuts', () {
    test('Ctrl+F, Ctrl+N, Ctrl+S and Esc each map to one intent', () {
      final map = desktopShortcutMap();
      Intent? find(LogicalKeyboardKey key, {bool ctrl = false}) {
        for (final e in map.entries) {
          final a = e.key as SingleActivator;
          if (a.trigger == key && a.control == ctrl) return e.value;
        }
        return null;
      }

      expect(find(LogicalKeyboardKey.keyF, ctrl: true), isA<FocusSearchIntent>());
      expect(find(LogicalKeyboardKey.keyN, ctrl: true), isA<NewContactIntent>());
      expect(find(LogicalKeyboardKey.keyS, ctrl: true), isA<SaveIntent>());
      expect(find(LogicalKeyboardKey.escape), isA<GoBackIntent>());
      expect(find(LogicalKeyboardKey.keyF), isNull, reason: 'plain F is just typing');
      expect(map.length, 4);
    });
  });

  group('dropped files', () {
    test('sorted by extension, in any case', () {
      expect(classifyDrop(r'C:\x\Contacts.VCF'), DropKind.vcard);
      expect(classifyDrop('/home/a/people.csv'), DropKind.csv);
      expect(classifyDrop('card.JPG'), DropKind.image);
      expect(classifyDrop('card.jpeg'), DropKind.image);
      expect(classifyDrop('card.png'), DropKind.image);
      expect(classifyDrop('CardKeep backup.zip'), DropKind.backup);
      expect(classifyDrop('notes.txt'), DropKind.ignored);
      expect(classifyDrop('folder'), DropKind.ignored);
    });

    test('one line says what arrived', () {
      expect(describeDrop(classifyDrops(['a.vcf', 'b.vcf', 'c.jpg'])), '2 contact files, 1 card photo');
      expect(describeDrop(classifyDrops(['a.csv', 'x.exe'])), '1 spreadsheet (1 skipped)');
      expect(describeDrop(classifyDrops(['x.exe'])), 'CardKeep cannot use that file.');
      expect(describeDrop(classifyDrops(['x.exe', 'y.dll'])), 'CardKeep cannot use those files.');
      expect(describeDrop(const []), 'Nothing was dropped.');
    });

    test('only the card photos are taken from a mixed drop, in order', () {
      expect(imagePaths(['b.png', 'a.vcf', 'c.JPG', 'd.txt']), ['b.png', 'c.JPG']);
    });

    test('a folder import lists its photos by name and skips everything else', () {
      final dir = Directory.systemTemp.createTempSync('ck_folder');
      addTearDown(() => dir.deleteSync(recursive: true));
      for (final n in ['b.jpg', 'A.png', 'notes.txt', 'c.vcf']) {
        File('${dir.path}/$n').writeAsBytesSync([1, 2, 3]);
      }
      Directory('${dir.path}/sub').createSync();
      File('${dir.path}/sub/z.jpg').writeAsBytesSync([1]);
      final names = imagesInFolder(dir).map((p) => p.split(Platform.pathSeparator).last).toList();
      expect(names, ['A.png', 'b.jpg'], reason: 'sorted ignoring case; the sub-folder is not entered');
    });
  });

  group('the window remembers where it was', () {
    test('what is saved is read back', () {
      const b = WindowBounds(120, 80, 1280, 800, maximized: true);
      final back = WindowBounds.decode(b.encode())!;
      expect([back.left, back.top, back.width, back.height, back.maximized], [120, 80, 1280, 800, true]);
    });

    test('damaged or tiny values are ignored', () {
      expect(WindowBounds.decode(null), isNull);
      expect(WindowBounds.decode(''), isNull);
      expect(WindowBounds.decode('{not json'), isNull);
      expect(WindowBounds.decode('{"l":0,"t":0,"w":100,"h":100,"max":false}'), isNull);
    });

    test('a window left on an unplugged monitor comes back to the first screen', () {
      const screens = [Rect.fromLTWH(0, 0, 1920, 1080)];
      const away = WindowBounds(3000, 200, 1200, 800);
      final fixed = away.onScreen(screens);
      expect(fixed.left, lessThan(1920));
      expect(fixed.width, 1200);
      const fine = WindowBounds(100, 100, 1200, 800);
      expect(fine.onScreen(screens).left, 100);
    });

    test('a window bigger than the screen is made to fit when it has to move', () {
      const screens = [Rect.fromLTWH(0, 0, 1366, 768)];
      final fixed = const WindowBounds(5000, 5000, 2400, 1500).onScreen(screens);
      expect(fixed.width, lessThanOrEqualTo(1366));
      expect(fixed.height, lessThanOrEqualTo(768));
    });
  });
}
