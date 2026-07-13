import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:donefirst/widgets/kid_device_lock_config_banner.dart';
import 'package:donefirst/supabase_config.dart';

/// Tests for the kid-device warning banner shown on
/// `lock_config_screen` when the chosen child has no paired
/// device. The banner is extracted into its own widget precisely
/// so it can be rendered in isolation — the screen itself drags
/// in Supabase services that aren't safe to mount without a live
/// backend.
///
/// Verifying the banner here means a future refactor that drops
/// the conditional or changes the copy has to break a test, not
/// surprise a parent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await initSupabase();
    } catch (_) {
      // Banner doesn't read from Supabase.
    }
  });

  group('KidDeviceLockConfigBanner', () {
    testWidgets('renders the warning copy with the child name and Pair now CTA',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KidDeviceLockConfigBanner(
              childName: 'Ada',
              onPair: () => taps++,
            ),
          ),
        ),
      );

      expect(
        find.textContaining("Pair Ada's phone first"),
        findsOneWidget,
      );
      expect(
        find.textContaining("won't be enforced on the kid's device"),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Pair now'), findsOneWidget);
    });

    testWidgets('uses the supplied child name verbatim', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: KidDeviceLockConfigBanner(
              childName: 'Bilal',
              onPair: _noop,
            ),
          ),
        ),
      );

      expect(
        find.textContaining("Pair Bilal's phone first"),
        findsOneWidget,
      );
      // The "Ada" copy must not appear — proves the name param is
      // actually plugged in rather than a hardcoded fallback.
      expect(find.textContaining("Ada"), findsNothing);
    });

    testWidgets('fires onPair when the CTA is tapped', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KidDeviceLockConfigBanner(
              childName: 'Ada',
              onPair: () => taps++,
            ),
          ),
        ),
      );

      await tester.tap(find.widgetWithText(TextButton, 'Pair now'));
      expect(taps, 1);
    });
  });
}

void _noop() {}
