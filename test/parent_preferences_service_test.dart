import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:donefirst/services/parent_preferences_service.dart';

void main() {
  group('ParentPreferencesService', () {
    setUp(() {
      // SharedPreferences.getInstance reads from a platform channel
      // that isn't wired in unit tests; the in-memory mock keeps the
      // tests offline-safe.
      SharedPreferences.setMockInitialValues({});
    });

    test('default values when nothing is stored', () async {
      final svc = ParentPreferencesService();
      expect(await svc.getPin(), isNull);
      expect(await svc.getAutoApproveMath(), isFalse);
      expect(await svc.getDefaultMinutes(), ParentPreferencesService.defaultMinutes);
    });

    test('round-trip PIN persists across new service instances', () async {
      final svc = ParentPreferencesService();
      await svc.setPin('1234');
      expect(await ParentPreferencesService().getPin(), '1234');
    });

    test('clearing PIN returns null', () async {
      final svc = ParentPreferencesService();
      await svc.setPin('4321');
      await svc.setPin(null);
      expect(await svc.getPin(), isNull);
    });

    test('getPin ignores values that are not exactly 4 digits', () async {
      // setPin stores verbatim; getPin defensively returns null for
      // any length != 4 so callers can trust a non-null result. This
      // protects against a manual SharedPreferences edit or a future
      // regression that lets an invalid PIN through.
      final svc = ParentPreferencesService();
      await svc.setPin('999');
      expect(await svc.getPin(), isNull);
      await svc.setPin('12345');
      expect(await svc.getPin(), isNull);
      await svc.setPin('1234');
      expect(await svc.getPin(), '1234');
    });

    test('round-trip auto-approve-math flag', () async {
      final svc = ParentPreferencesService();
      await svc.setAutoApproveMath(true);
      expect(await ParentPreferencesService().getAutoApproveMath(), isTrue);
      await svc.setAutoApproveMath(false);
      expect(await ParentPreferencesService().getAutoApproveMath(), isFalse);
    });

    test('round-trip default-minutes for every allowed value', () async {
      for (final m in ParentPreferencesService.allowedMinutes) {
        final svc = ParentPreferencesService();
        await svc.setDefaultMinutes(m);
        expect(
          await ParentPreferencesService().getDefaultMinutes(),
          m,
          reason: 'round-trip failed for $m',
        );
      }
    });

    test('default-minutes clamps out-of-range to nearest allowed', () async {
      final svc = ParentPreferencesService();
      // 25 should clamp to 30 (closest).
      await svc.setDefaultMinutes(25);
      expect(await svc.getDefaultMinutes(), 30);
      // 200 should clamp to 120 (max allowed).
      await svc.setDefaultMinutes(200);
      expect(await svc.getDefaultMinutes(), 120);
    });
  });
}
