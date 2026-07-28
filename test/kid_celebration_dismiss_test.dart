import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:donefirst/screens/kid/unlocked_screen.dart';
import 'package:donefirst/supabase_config.dart';

/// "Approved. You're free." used to be a dead end. The flag behind it
/// (KidRealtimeService._justFinishedSession) was only cleared when the
/// *next* session started, and the celebration itself carried no
/// control that dismissed it — so a kid who finished their homework
/// was parked on a congratulations screen for the rest of the day,
/// with no streak, no next-session card, and no way to add tomorrow's
/// tasks. Relaunching the app was the only way back to Today.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    try {
      await initSupabase();
    } catch (_) {
      // Offline is fine — StreakService only needs the instance to
      // exist so UnlockedScreen can construct. The fetch failing just
      // holds the stat tiles at "—", which is what we want here.
    }
  });

  testWidgets('the celebration offers a way back to Today', (tester) async {
    var dismissed = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: UnlockedScreen(
          childName: 'Robin',
          celebrate: true,
          onDone: () => dismissed++,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Approved.'), findsOneWidget);

    final backToToday = find.text('Back to today');
    expect(
      backToToday,
      findsOneWidget,
      reason: 'without this the screen cannot be left',
    );

    await tester.tap(backToToday);
    await tester.pump();
    expect(dismissed, 1);
  });

  testWidgets('the idle "All clear" rendering has nothing to dismiss', (
    tester,
  ) async {
    // This one is reached *from* Today rather than instead of it, so
    // a "Back to today" control there would be a no-op loop.
    await tester.pumpWidget(
      const MaterialApp(home: UnlockedScreen(childName: 'Robin')),
    );
    await tester.pump();

    expect(find.text('All clear.'), findsOneWidget);
    expect(find.text('Back to today'), findsNothing);
  });
}
