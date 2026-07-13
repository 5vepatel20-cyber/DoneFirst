import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:donefirst/widgets/kid_device_status_caption.dart';
import 'package:donefirst/supabase_config.dart';

/// Tests for the dashboard's per-child kid-device status caption.
///
/// The caption has five states (online / recent / stale / revoked /
/// null) and the null state is the only one that exposes a tap
/// action. We verify each state's label + colour cue, the
/// "Last seen" second line, and the onPair contract on the null
/// state. The widget is extracted from the dashboard precisely so
/// these can be tested without dragging in Supabase services.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await initSupabase();
    } catch (_) {
      // Widget doesn't read from Supabase.
    }
  });

  group('KidDeviceStatusCaption labels', () {
    testWidgets('renders "No device paired" for null status', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: KidDeviceStatusCaption(status: null)),
      ));
      expect(find.text('No device paired'), findsOneWidget);
      expect(find.textContaining('Last seen'), findsNothing);
    });

    testWidgets('renders "Device online" for online status',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: KidDeviceStatusCaption(status: 'online')),
      ));
      expect(find.text('Device online'), findsOneWidget);
    });

    testWidgets('renders "Device idle" for recent status', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: KidDeviceStatusCaption(status: 'recent')),
      ));
      expect(find.text('Device idle'), findsOneWidget);
    });

    testWidgets('renders "Device offline" for stale status',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: KidDeviceStatusCaption(status: 'stale')),
      ));
      expect(find.text('Device offline'), findsOneWidget);
    });

    testWidgets('renders "Device revoked" for revoked status',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: KidDeviceStatusCaption(status: 'revoked')),
      ));
      expect(find.text('Device revoked'), findsOneWidget);
      // Revoked + lastSeenAt shouldn't render "Last seen" — the
      // device is no longer reporting.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: KidDeviceStatusCaption(
            status: 'revoked',
            lastSeenAt: DateTime.now(),
          ),
        ),
      ));
      expect(find.textContaining('Last seen'), findsNothing);
    });
  });

  group('KidDeviceStatusCaption Last seen line', () {
    testWidgets('shows "Just now" for a fresh heartbeat', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: KidDeviceStatusCaption(
            status: 'online',
            lastSeenAt: DateTime.now(),
          ),
        ),
      ));
      expect(find.textContaining('Just now'), findsOneWidget);
    });

    testWidgets('shows minutes-ago for a heartbeat a few minutes back',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: KidDeviceStatusCaption(
            status: 'recent',
            lastSeenAt: DateTime.now().subtract(const Duration(minutes: 7)),
          ),
        ),
      ));
      expect(find.textContaining('7 min ago'), findsOneWidget);
    });

    testWidgets('hides Last seen when status is null even with a timestamp',
        (tester) async {
      // The widget's contract: "Last seen" only renders when the
      // status is online/recent/stale. A null status means there's
      // no device at all, so a stray timestamp shouldn't drive a
      // second-line render.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: KidDeviceStatusCaption(
            status: null,
            lastSeenAt: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
        ),
      ));
      expect(find.textContaining('Last seen'), findsNothing);
    });
  });

  group('KidDeviceStatusCaption pair CTA', () {
    testWidgets('fires onPair when the null-status label is tapped',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: KidDeviceStatusCaption(
            status: null,
            onPair: () => taps++,
          ),
        ),
      ));
      await tester.tap(find.text('No device paired'));
      expect(taps, 1);
    });

    testWidgets('does not fire onPair when status is non-null',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: KidDeviceStatusCaption(
            status: 'online',
            onPair: () => taps++,
          ),
        ),
      ));
      // onPair is wired but the widget should ignore it for active
      // statuses. We pass it through anyway so callers don't have
      // to null-check the callback.
      await tester.tap(find.text('Device online'));
      expect(taps, 0);
    });

    testWidgets('shows a chevron on the null-state caption as a CTA cue',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: KidDeviceStatusCaption(
            status: null,
            onPair: () {},
          ),
        ),
      ));
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('does not show a chevron on active states', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: KidDeviceStatusCaption(status: 'online')),
      ));
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });
  });
}
