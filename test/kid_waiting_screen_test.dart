import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:donefirst/screens/kid/waiting_screen.dart';
import 'package:donefirst/services/heartbeat_service.dart';
import 'package:donefirst/services/kid_auth_service.dart';
import 'package:donefirst/supabase_config.dart';

/// The waiting screen used to tell every kid the same thing —
/// "Waiting for your next session to start" — whether their app was
/// mid-handshake or their pairing was dead for good. The second case
/// never resolves on its own, so that sentence left a kid staring at a
/// screen that would never change, with no hint anyone had to act.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    try {
      await initSupabase();
    } catch (_) {
      // No live backend needed; the screen only constructs services.
    }
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  HeartbeatService heartbeat() =>
      HeartbeatService(kidAuth: KidAuthService());

  Widget host(Widget child) => MaterialApp(home: child);

  Future<void> settle(WidgetTester tester) async {
    // The screen polls heartbeat every 5s forever, so pumpAndSettle
    // would time out. Unmount, then drain the pending timers.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  }

  testWidgets('connecting is calm and makes no promises', (tester) async {
    await tester.pumpWidget(
      host(
        WaitingScreen(
          reason: KidWaitingReason.connecting,
          onReconnect: () {},
          heartbeat: heartbeat(),
          childName: 'Ada',
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Getting things ready'), findsOneWidget);
    // No alarm, and crucially no claim about their homework.
    expect(find.text('Can’t reach your parent’s app'), findsNothing);

    await settle(tester);
  });

  testWidgets('disconnected names the problem and the fix', (tester) async {
    await tester.pumpWidget(
      host(
        WaitingScreen(
          reason: KidWaitingReason.disconnected,
          onReconnect: () {},
          heartbeat: heartbeat(),
          childName: 'Ada',
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Can’t reach your parent’s app'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // The step that was missing entirely: a rotated refresh token
    // cannot be recovered on the device, so someone has to re-pair.
    expect(find.textContaining('pair this device again'), findsOneWidget);
    // And the reassurance a kid actually needs.
    expect(find.textContaining('Your apps are open'), findsOneWidget);

    await settle(tester);
  });

  testWidgets('connecting escalates rather than spinning forever', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        WaitingScreen(
          reason: KidWaitingReason.connecting,
          onReconnect: () {},
          heartbeat: heartbeat(),
          childName: 'Ada',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Getting things ready'), findsOneWidget);

    // Past the point where "connecting" is still a credible story.
    await tester.pump(const Duration(seconds: 26));

    expect(find.text('Can’t reach your parent’s app'), findsOneWidget);
    expect(find.textContaining('pair this device again'), findsOneWidget);

    await settle(tester);
  });

  testWidgets('Try again calls back into reconnect', (tester) async {
    var reconnects = 0;
    await tester.pumpWidget(
      host(
        WaitingScreen(
          reason: KidWaitingReason.disconnected,
          onReconnect: () => reconnects++,
          heartbeat: heartbeat(),
          childName: 'Ada',
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Try again'));
    await tester.pump();

    expect(reconnects, 1);

    await settle(tester);
  });

  testWidgets('renders without a child name', (tester) async {
    await tester.pumpWidget(
      host(
        WaitingScreen(
          reason: KidWaitingReason.disconnected,
          onReconnect: () {},
          heartbeat: heartbeat(),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Can’t reach your parent’s app'), findsOneWidget);

    await settle(tester);
  });
}
