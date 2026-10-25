import 'package:card_organizer/features/about/about_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('split-APK version codes show the real pubspec build number', () {
    expect(displayBuildNumber('2017'), '17', reason: 'arm64-v8a adds 2000');
    expect(displayBuildNumber('1017'), '17', reason: 'armeabi-v7a adds 1000');
    expect(displayBuildNumber('4018'), '18', reason: 'x86_64 adds 4000');
    expect(displayBuildNumber('18'), '18', reason: 'a plain build is unchanged');
    expect(displayBuildNumber('2118'), '118', reason: 'builds over 99 keep their digits');
  });

  test('a build number that is not a number is shown as it is', () {
    expect(displayBuildNumber(''), '');
    expect(displayBuildNumber('abc'), 'abc');
  });
}
