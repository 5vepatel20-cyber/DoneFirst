import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:donefirst/screens/kid/unlocked_screen.dart';
import 'package:donefirst/supabase_config.dart';

/// The kid's "you're free" screen used to always render a
/// "Done — open my apps" button wired to SystemNavigator.pop(). That
/// call is a no-op on web and on iOS (an app can't terminate itself),
/// so on those platforms the kid tapped a button that did nothing.
///
/// These tests pin the platform split: the exit button exists only
/// where there's actually a launcher to hand back to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // AppText pulls Bricolage/Hanken through google_fonts, which
    // otherwise tries to fetch over the network mid-test and reports
    // as "test failed after it had already completed".
    GoogleFonts.config.allowRuntimeFetching = false;
    // UnlockedScreen builds a StreakService, which reads
    // Supabase.instance.client in its field initializer.
    SharedPreferences.setMockInitialValues({});
    try {
      await initSupabase();
    } catch (_) {
      // No network in CI — Supabase.instance is still populated,
      // which is all the widget needs to construct.
    }
  });

  /// Pump the screen as [platform]. childId is null so the screen
  /// skips its stats fetch and the test never touches the network.
  ///
  /// The override is cleared before the body returns rather than in
  /// tearDown: flutter_test asserts foundation debug vars are unset
  /// at the end of the test body, which runs first.
  Future<void> pumpUnlockedAs(
    WidgetTester tester,
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await tester.pumpWidget(
        const MaterialApp(home: UnlockedScreen(childName: 'Maya')),
      );
      await tester.pump();
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('Android keeps the exit-to-launcher button', (tester) async {
    await pumpUnlockedAs(tester, TargetPlatform.android, () async {
      expect(find.text('Done — open my apps'), findsOneWidget);
    });
  });

  testWidgets('iOS shows a statement instead of a dead button', (
    tester,
  ) async {
    await pumpUnlockedAs(tester, TargetPlatform.iOS, () async {
      expect(find.text('Done — open my apps'), findsNothing);
      expect(
        find.text('Your apps are unlocked — go enjoy them.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('stats stay on the placeholder instead of printing 0', (
    tester,
  ) async {
    await pumpUnlockedAs(tester, TargetPlatform.iOS, () async {
      expect(find.text('Approved.'), findsOneWidget);
      expect(find.text("You're free."), findsOneWidget);
      // Without a childId the numbers never resolve, so no tile may
      // claim a real zero.
      expect(find.text('0'), findsNothing);
      expect(find.text('0m'), findsNothing);
    });
  });
}
