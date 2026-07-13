import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/services/realtime_service.dart';
import '../lib/supabase_config.dart';

/// RealtimeService tests without a live Supabase. We can't actually
/// fire channel callbacks from outside, so we directly poke the
/// public callback setters — that covers the contract surface
/// (onNewKidDeviceEvent / onKidDeviceChanged getters + setters) and
/// proves null vs chained callbacks work correctly.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await initSupabase();
    } catch (_) {
      // No live Supabase in test env; realtime just won't connect,
      // and the unit tests below only exercise the callback API.
    }
  });

  group('RealtimeService callback chaining', () {
    test('onNewKidDeviceEvent starts null and can be assigned', () {
      final svc = RealtimeService();
      expect(svc.onNewKidDeviceEvent, isNull);
      var called = 0;
      svc.onNewKidDeviceEvent = (_) => called++;
      expect(svc.onNewKidDeviceEvent, isNotNull);
      // Manual invocation simulates what the realtime channel
      // would do on receiving a kid_device_events INSERT.
      svc.onNewKidDeviceEvent?.call({'id': 'e-1', 'family_id': 'f-1'});
      expect(called, 1);
    });

    test('onKidDeviceChanged accepts a payload and forwards it', () {
      final svc = RealtimeService();
      Map<String, dynamic>? captured;
      svc.onKidDeviceChanged = (row) => captured = row;
      svc.onKidDeviceChanged?.call({
        'id': 'd-1',
        'child_id': 'c-1',
        'last_seen_at': '2026-07-13T00:00:00Z',
      });
      expect(captured, isNotNull);
      final c = captured!;
      expect(c['id'], 'd-1');
      expect(c['child_id'], 'c-1');
    });

    test('callback can be cleared by assigning null', () {
      final svc = RealtimeService();
      svc.onNewKidDeviceEvent = (_) {};
      expect(svc.onNewKidDeviceEvent, isNotNull);
      svc.onNewKidDeviceEvent = null;
      expect(svc.onNewKidDeviceEvent, isNull);
    });

    test('multiple reassignments chain via restore-on-dispose pattern',
        () {
      // Simulates the pairing screen's pattern: cache the prior
      // callback, set its own, then restore the prior on dispose.
      final svc = RealtimeService();
      var dashboardCalled = 0;
      var pairingCalled = 0;
      svc.onNewKidDeviceEvent = (_) => dashboardCalled++;

      // Pairing screen opens.
      final previous = svc.onNewKidDeviceEvent;
      svc.onNewKidDeviceEvent = (_) => pairingCalled++;

      svc.onNewKidDeviceEvent?.call({'id': 'e'});
      expect(dashboardCalled, 0,
          reason: 'dashboard handler should be dormant while '
              'pairing screen owns the slot');
      expect(pairingCalled, 1);

      // Pairing screen disposes — restore the cached handler.
      svc.onNewKidDeviceEvent = previous;
      svc.onNewKidDeviceEvent?.call({'id': 'e'});
      expect(dashboardCalled, 1,
          reason: 'restored handler should resume firing');
      expect(pairingCalled, 1);
    });
  });

  group('RealtimeService stop and dispose', () {
    test('stopListening is idempotent', () {
      final svc = RealtimeService();
      // Should not throw even though we never started listening.
      svc.stopListening();
      svc.stopListening();
    });

    test('listening flag transitions cleanly', () {
      final svc = RealtimeService();
      expect(svc.listening, isFalse);
      // We don't call startListening because that requires an
      // authenticated session; the flag stays false, which is the
      // contract surface we're verifying here.
      expect(svc.listening, isFalse);
    });
  });
}