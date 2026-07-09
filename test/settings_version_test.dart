// Stable-string guard: the "About" section in settings renders the
// app version literally. We don't ship `package_info_plus` yet, so the
// version is a const string that must be updated by hand in tandem
// with pubspec.yaml. This test makes sure the two stay in sync.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SettingsScreen _appVersion matches pubspec.yaml', () async {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final line = pubspec
        .split('\n')
        .firstWhere((l) => l.startsWith('version:'), orElse: () => '');
    // version: 1.0.0+1  ->  take everything before the '+'
    final versionStr = line.split(':').last.trim().split('+').first;
    final settingsSrc = File(
      'lib/screens/settings_screen.dart',
    ).readAsStringSync();
    expect(
      settingsSrc.contains("_appVersion = '$versionStr'"),
      isTrue,
      reason: 'settings_screen.dart _appVersion constant must '
          'match the major in pubspec.yaml (currently $versionStr). '
          'Bump both together before a release.',
    );
  });
}
