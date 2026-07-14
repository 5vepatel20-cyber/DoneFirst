import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:donefirst/app_globals.dart' as app;
import 'package:donefirst/screens/kid_device_activity_screen.dart';
import 'package:donefirst/supabase_config.dart';

/// Tests for the kid-device activity screen. The screen pulls
/// events from KidDeviceEventService which goes through Supabase
/// — without a live backend, the fetch throws and we land in the
/// error empty state. That's still a useful surface to verify:
/// AppBar title, error copy, pull-to-refresh affordance.
///
/// The success path is harder to test without mocking Supabase,
/// so the "row icon/colour" mapping is exercised by the recent
/// card's existing tests instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await initSupabase();
    } catch (_) {
      // Live Supabase not available; the screen's service call
      // throws and the error empty-state fires.
    }
  });

  setUp(() {
    // Reset the global realtime slot between tests so a prior
    // test's handler doesn't leak.
    app.realtimeService.onNewKidDeviceEvent = null;
  });

  group('KidDeviceActivityScreen', () {
    testWidgets('renders the Activity appbar title', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: KidDeviceActivityScreen(),
      ));
      // Pump once for the initial frame, then settle for the
      // async load to complete (it'll fail and the empty-state
      // body will mount).
      await tester.pumpAndSettle();

      expect(find.text('Activity'), findsOneWidget);
    });

    testWidgets('shows the error empty state when the fetch fails',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: KidDeviceActivityScreen(),
      ));
      await tester.pumpAndSettle();

      // The error empty state has a distinct title so the parent
      // can tell "we tried" from "no events yet".
      expect(find.text('Could not load activity'), findsOneWidget);
      expect(find.textContaining('Pull down to try again'), findsOneWidget);
    });

    testWidgets('wires onNewKidDeviceEvent on mount, restores on dispose',
        (tester) async {
      void prior(Map<String, dynamic> _) {}
      app.realtimeService.onNewKidDeviceEvent = prior;
      final priorRef = app.realtimeService.onNewKidDeviceEvent;
      expect(priorRef, isNotNull);

      await tester.pumpWidget(const MaterialApp(
        home: KidDeviceActivityScreen(),
      ));

      // The screen installed its own handler; the prior one is
      // chained inside the screen, not on the service.
      expect(app.realtimeService.onNewKidDeviceEvent, isNotNull);
      expect(
        identical(app.realtimeService.onNewKidDeviceEvent, prior),
        isFalse,
      );

      // Replace the tree with an empty one to trigger dispose.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      // The screen's handler restored the prior — the same
      // function reference should be back on the service.
      expect(identical(app.realtimeService.onNewKidDeviceEvent, prior), isTrue);
    });
  });
}
