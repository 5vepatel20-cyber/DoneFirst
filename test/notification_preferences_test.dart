// Tests for NotificationPreferencesService (SharedPreferences-backed).
//
// We use the SharedPreferences.setMockInitialValues test helper so the
// file is unit-testable without writing to disk.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:donefirst/services/notification_preferences_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('NotificationPreferencesService', () {
    final service = NotificationPreferencesService();

    test('defaultPrefs has every spec type enabled', () {
      final defaults = NotificationPreferencesService.defaultPrefs();
      for (final spec in NotificationPreferencesService.specs) {
        expect(defaults[spec.type], spec.defaultEnabled,
            reason: 'Spec ${spec.type} default should match its spec');
      }
    });

    test('all spec types are unique', () {
      final types = NotificationPreferencesService.specs
          .map((s) => s.type)
          .toSet();
      expect(types.length, NotificationPreferencesService.specs.length,
          reason: 'Spec types must be unique');
    });

    test('getPrefs returns defaults when nothing is stored', () async {
      final prefs = await service.getPrefs();
      expect(prefs, NotificationPreferencesService.defaultPrefs());
    });

    test('isEnabled returns the stored value', () async {
      await service.setEnabled(
        NotificationPreferencesService.typeBreakRequested,
        false,
      );
      expect(
        await service.isEnabled(
          NotificationPreferencesService.typeBreakRequested,
        ),
        isFalse,
      );
      // Other types still default to true.
      expect(
        await service.isEnabled(
          NotificationPreferencesService.typeProofSubmitted,
        ),
        isTrue,
      );
    });

    test('setEnabled persists across instances', () async {
      await service.setEnabled(
        NotificationPreferencesService.typeSessionComplete,
        false,
      );
      final other = NotificationPreferencesService();
      final prefs = await other.getPrefs();
      expect(
        prefs[NotificationPreferencesService.typeSessionComplete],
        isFalse,
      );
    });

    test('resetToDefaults restores all-on', () async {
      await service.setEnabled(
        NotificationPreferencesService.typeProofSubmitted,
        false,
      );
      await service.setEnabled(
        NotificationPreferencesService.typeBreakRequested,
        false,
      );
      await service.resetToDefaults();
      final prefs = await service.getPrefs();
      expect(prefs, NotificationPreferencesService.defaultPrefs());
    });

    test('storage round-trips arbitrary toggles', () async {
      // Verify encoding: "key=1" or "key=0", recoverable on next read.
      await service.setEnabled('unknown_type', true);
      // Adding a key the spec doesn't know about must not crash
      // the next getPrefs — but isEnabled('unknown_type') on a
      // reader that doesn't know about it is the caller's problem.
      // (NotificationService uses spec constants only.)
      final prefs = await service.getPrefs();
      expect(prefs['unknown_type'], isTrue);
    });
  });
}
