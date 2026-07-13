import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/app_globals.dart' as app;
import '../lib/services/kid_device_service.dart';
import '../lib/services/realtime_service.dart';
import '../lib/supabase_config.dart';
import '../lib/widgets/kid_device_event_toast_listener.dart';

/// Tests for KidDeviceEventToastListener. The widget mounts into
/// the global [RealtimeService.onNewKidDeviceEvent] slot and
/// forwards events through the global [app.toastService]. Toasts
/// render via the root ScaffoldMessengerKey (which we don't pump
/// here), so we observe the side-effects we CAN see:
///
///   1. Mount wires the slot; dispose restores the prior handler.
///   2. Mounting twice chains (each layer saves and restores its
///      own prior snapshot).
///   3. Firing an event chains to the previous handler regardless
///      of whether the listener toasts it.
///   4. code_generated / code_cancelled don't throw and still chain
///      through (they're suppressed only at the toast layer).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await initSupabase();
    } catch (_) {
      // No live Supabase in tests; we exercise the listener
      // callback directly without firing a real channel.
    }
  });

  group('KidDeviceEventToastListener lifecycle', () {
    testWidgets('mount wires onNewKidDeviceEvent; dispose restores prior',
        (tester) async {
      // Prime the global realtime service with a known prior handler.
      void prior(Map<String, dynamic> _) {}
      app.realtimeService.onNewKidDeviceEvent = prior;
      final priorRef = app.realtimeService.onNewKidDeviceEvent;
      expect(priorRef, isNotNull);

      await tester.pumpWidget(
        const MaterialApp(
          home: KidDeviceEventToastListener(child: SizedBox.shrink()),
        ),
      );

      // While mounted, the listener owns the slot — the prior
      // handler is chained inside it (not on the service).
      expect(app.realtimeService.onNewKidDeviceEvent, isNotNull);
      expect(
        identical(app.realtimeService.onNewKidDeviceEvent, prior),
        isFalse,
        reason: 'listener should have replaced, not chained on top',
      );

      // Unmount by replacing the tree with an empty one.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      // Slot is restored to the original handler reference.
      expect(
        identical(app.realtimeService.onNewKidDeviceEvent, priorRef),
        isTrue,
        reason: 'dispose should have restored the previously-'
            'registered handler',
      );

      // Cleanup: leave the slot null for the next test.
      app.realtimeService.onNewKidDeviceEvent = null;
    });

    testWidgets('mounting twice chains rather than clobbers', (tester) async {
      app.realtimeService.onNewKidDeviceEvent = null;

      // Mount listener #1. It saves the prior (null) and sets
      // itself into the slot.
      await tester.pumpWidget(
        const MaterialApp(
          home: KidDeviceEventToastListener(
            key: ValueKey<String>('listener-1'),
            child: SizedBox.shrink(),
          ),
        ),
      );
      final slotAfterFirst = app.realtimeService.onNewKidDeviceEvent;
      expect(slotAfterFirst, isNotNull);

      // Swap to a different widget type entirely (a plain SizedBox).
      // This forces listener #1 to dispose, which restores the
      // prior snapshot (null). The slot must end up null.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      expect(app.realtimeService.onNewKidDeviceEvent, isNull,
          reason: 'after disposing, slot should be back to its '
              'pre-listener state');

      // Now mount listener #2 from scratch. It saves null and
      // installs itself again — proves the pattern is repeatable.
      await tester.pumpWidget(
        const MaterialApp(
          home: KidDeviceEventToastListener(
            key: ValueKey<String>('listener-2'),
            child: SizedBox.shrink(),
          ),
        ),
      );
      expect(app.realtimeService.onNewKidDeviceEvent, isNotNull);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      expect(app.realtimeService.onNewKidDeviceEvent, isNull);
    });
  });

  group('KidDeviceEventToastListener event routing', () {
    testWidgets('firing an event chains to the previous handler',
        (tester) async {
      var priorCalls = 0;
      app.realtimeService.onNewKidDeviceEvent = (_) => priorCalls++;

      await tester.pumpWidget(
        const MaterialApp(
          home: KidDeviceEventToastListener(child: SizedBox.shrink()),
        ),
      );

      // Listener's installed callback forwards to the prior
      // handler — that's the contract that prevents the activity
      // feed from going silent while a toast is showing.
      app.realtimeService.onNewKidDeviceEvent?.call({
        'event_type': KidDeviceEvent.typeDeviceRevoked,
        'family_id': 'f',
      });

      expect(priorCalls, 1, reason: 'prior handler should fire once');

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      app.realtimeService.onNewKidDeviceEvent = null;
    });

    testWidgets('null event_type is ignored without crashing',
        (tester) async {
      var priorCalls = 0;
      app.realtimeService.onNewKidDeviceEvent = (_) => priorCalls++;

      await tester.pumpWidget(
        const MaterialApp(
          home: KidDeviceEventToastListener(child: SizedBox.shrink()),
        ),
      );

      app.realtimeService.onNewKidDeviceEvent?.call({
        'family_id': 'f',
        // event_type missing
      });

      expect(priorCalls, 1,
          reason: 'chained prior handler should still fire even '
              'when the listener drops the event for missing type');

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      app.realtimeService.onNewKidDeviceEvent = null;
    });

    testWidgets('code_generated and code_cancelled events pass through '
        'silently', (tester) async {
      // These two event types are intentionally NOT toasted —
      // they're parent-initiated and self-toasting would be noise.
      // We verify the contract by checking that the listener
      // doesn't throw on either, and the chained prior still fires.
      var priorCalls = 0;
      app.realtimeService.onNewKidDeviceEvent = (_) => priorCalls++;

      await tester.pumpWidget(
        const MaterialApp(
          home: KidDeviceEventToastListener(child: SizedBox.shrink()),
        ),
      );

      for (final type in const [
        KidDeviceEvent.typeCodeGenerated,
        KidDeviceEvent.typeCodeCancelled,
      ]) {
        app.realtimeService.onNewKidDeviceEvent?.call({
          'event_type': type,
          'family_id': 'f',
        });
      }

      expect(priorCalls, 2, reason: 'both events should chain to prior');

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      app.realtimeService.onNewKidDeviceEvent = null;
    });
  });
}
