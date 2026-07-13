import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/supabase_config.dart';
import '../lib/widgets/kid_device_setup_hint_card.dart';

/// Smoke tests for the dashboard's "no kid device paired" hint
/// card. Verifies it renders the headline + subhead and that
/// the action button is a real tappable target.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await initSupabase();
    } catch (_) {
      // Card itself doesn't read from Supabase.
    }
  });

  testWidgets('renders headline, subhead, and setup button',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: KidDeviceSetupHintCard()),
      ),
    );

    expect(find.text('Lock apps on your kid\'s phone'), findsOneWidget);
    expect(find.textContaining('Pair the DoneFirst Kid app'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pair now'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Setup guide'), findsOneWidget);

    // Tapping either action doesn't throw. We can't easily assert
    // navigation to the real screens here without dragging the
    // not-yet-built kid-app services into the test graph.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Setup guide'));
    await tester.pump();
  });

  testWidgets('honours firstChildId when provided', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KidDeviceSetupHintCard(firstChildId: 'child-xyz'),
        ),
      ),
    );

    // firstChildId isn't directly observable from the UI, but the
    // card must render the same way — its presence only changes
    // the destination pushed on Pair-now tap. Smoke-test that
    // the widget builds without throwing when the parameter is
    // non-null.
    expect(find.byType(KidDeviceSetupHintCard), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pair now'), findsOneWidget);
  });
}