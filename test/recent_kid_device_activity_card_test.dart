import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/app_globals.dart' as app;
import '../lib/services/kid_device_service.dart';
import '../lib/supabase_config.dart';
import '../lib/widgets/recent_kid_device_activity_card.dart';

/// Smoke tests for RecentKidDeviceActivityCard. We can't fire
/// `KidDeviceEventService.listFamilyEvents` without a live Supabase,
/// so the tests verify the mount/unmount contract on the realtime
/// callback slot and that loading + empty states collapse to a
/// SizedBox.shrink() placeholder (so the dashboard doesn't reflow).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await initSupabase();
    } catch (_) {}
  });

  setUp(() {
    // Reset the global realtime callback slot so each test starts
    // clean. Without this, a previous test's chain could leak.
    app.realtimeService.onNewKidDeviceEvent = null;
  });

  testWidgets('mount wires onNewKidDeviceEvent; dispose restores prior',
      (tester) async {
    void prior(Map<String, dynamic> _) {}
    app.realtimeService.onNewKidDeviceEvent = prior;
    final priorRef = app.realtimeService.onNewKidDeviceEvent;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RecentKidDeviceActivityCard()),
      ),
    );

    expect(app.realtimeService.onNewKidDeviceEvent, isNotNull);
    expect(
      identical(app.realtimeService.onNewKidDeviceEvent, prior),
      isFalse,
      reason: 'card should have replaced, not chained on top',
    );

    // Replace with a non-card widget to trigger dispose.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(
      identical(app.realtimeService.onNewKidDeviceEvent, priorRef),
      isTrue,
      reason: 'dispose should have restored the prior handler',
    );
    app.realtimeService.onNewKidDeviceEvent = null;
  });

  testWidgets('chains to prior handler when an event fires', (tester) async {
    var priorCalls = 0;
    app.realtimeService.onNewKidDeviceEvent = (_) => priorCalls++;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RecentKidDeviceActivityCard()),
      ),
    );

    app.realtimeService.onNewKidDeviceEvent?.call({
      'event_type': KidDeviceEvent.typeCodeClaimed,
      'family_id': 'f',
    });
    expect(priorCalls, 1,
        reason: 'chained prior handler should fire even though '
            'the card is also re-fetching on the event');

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    app.realtimeService.onNewKidDeviceEvent = null;
  });

  testWidgets('loading state renders nothing visible', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RecentKidDeviceActivityCard()),
      ),
    );
    // Pump zero frames: initState fires _load() but the response
    // never resolves (no Supabase). The card should still render
    // a SizedBox.shrink so the dashboard reflow is minimal.
    expect(find.byType(Card), findsNothing,
        reason: 'loading state should not show the card chrome');

    // Let any pending microtasks settle, then re-check.
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(Card), findsNothing);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  });
}