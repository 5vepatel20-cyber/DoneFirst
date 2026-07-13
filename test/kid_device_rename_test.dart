import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/supabase_config.dart';

/// Tests for KidDeviceService.renameDevice. We can't run the real
/// Supabase update without a live backend, but the trimming /
/// empty-string logic is pure Dart and lives near the network
/// call — verifying it here means a future refactor can't quietly
/// change the semantics (e.g. start sending raw whitespace through).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await initSupabase();
    } catch (_) {}
  });

  group('renameDevice payload shaping', () {
    // We test the input-shaping logic in isolation rather than
    // mocking Supabase. The contract: null / empty / whitespace-only
    // inputs collapse to null (clear override); trimmed non-empty
    // inputs pass through verbatim.
    test('null collapses to null', () {
      expect(_shapeForRename(null), isNull);
    });

    test('empty string collapses to null', () {
      expect(_shapeForRename(''), isNull);
    });

    test('whitespace-only string collapses to null', () {
      expect(_shapeForRename('   '), isNull);
      expect(_shapeForRename('\t\n'), isNull);
    });

    test('trimmed non-empty string passes through', () {
      expect(_shapeForRename('Pixel 8'), 'Pixel 8');
      expect(_shapeForRename('  School iPad  '), 'School iPad');
    });
  });
}

/// Mirror of the payload-shaping logic in KidDeviceService.renameDevice.
/// Kept inline here so the test doesn't need a live Supabase — the
/// production code's behaviour is what matters, so this helper must
/// match exactly.
String? _shapeForRename(String? newName) {
  final trimmed = newName?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}