import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:donefirst/screens/kid/kid_root.dart';
import 'package:donefirst/screens/kid/pairing_screen.dart';
import 'package:donefirst/screens/splash_screen.dart';
import 'package:donefirst/supabase_config.dart';

/// KidRoot used to render PairingScreen on its very first frame,
/// before _bootstrap had a chance to restore the persisted kid
/// session. On web that window is seconds long — long enough for an
/// already-paired kid to see "Enter your code" flash past on every
/// launch, and long enough to start typing into it.
///
/// The first frame must be the neutral splash instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    try {
      await initSupabase();
    } catch (_) {
      // Offline is fine — the widgets only need Supabase.instance to
      // exist so the services can construct.
    }
  });

  testWidgets('first frame is the splash, not the pairing screen', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: KidRoot()));

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(
      find.byType(PairingScreen),
      findsNothing,
      reason: 'we do not know yet whether this device is paired',
    );
  });

  testWidgets('boot resolves off the splash once pairing is known', (
    tester,
  ) async {
    // The splash used to be held until the realtime subscription
    // landed, so a stalled socket left an unpaired kid staring at the
    // logo with nothing to tap. Boot now only waits on the "are we
    // paired?" answer — with no persisted tokens that's an immediate
    // no, and the pairing screen must appear.
    // runAsync so the SharedPreferences platform channel that
    // restoreSession waits on actually resolves.
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: KidRoot()));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(PairingScreen), findsOneWidget);
  });
}
