import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:donefirst/screens/kid/kid_shell.dart';
import 'package:donefirst/supabase_config.dart';

/// The kid device shipped with no navigation at all: the designed
/// four-tab app lived in kid_home_screen.dart, which only the *parent*
/// could open via "Kid view". These tests pin the tabs onto the kid's
/// own device so a future refactor can't quietly orphan them again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    try {
      await initSupabase();
    } catch (_) {
      // Offline is fine — the tabs only need Supabase.instance to
      // exist so the services can construct.
    }
  });

  Widget host(Widget child) => MaterialApp(home: child);

  testWidgets('all four designed tabs are present on the kid device', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const KidShell(childName: 'Ada', childId: 'child-1')),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Progress'), findsOneWidget);
    expect(find.text('Me'), findsOneWidget);
  });

  testWidgets('opens on Today', (tester) async {
    await tester.pumpWidget(
      host(const KidShell(childName: 'Ada', childId: 'child-1')),
    );
    await tester.pump();

    expect(find.text('Hi, Ada'), findsOneWidget);
  });

  testWidgets('tapping Me switches tabs without leaving the shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const KidShell(childName: 'Ada', childId: 'child-1')),
    );
    await tester.pump();

    await tester.tap(find.text('Me'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // The tab bar is still there — this is a tab switch, not a push
    // onto a new route that hides the navigation.
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Progress'), findsOneWidget);
    // Me renders the kid's own name rather than reading `children`,
    // which their JWT has no policy for.
    expect(find.text('Ada'), findsWidgets);
  });

  testWidgets('data tabs are inert until the child id arrives', (tester) async {
    // kid_root can build the shell before KidAuthService has restored
    // the kid's identity. Querying `child_id = null` would come back
    // 200 [] under RLS and render as "you have done nothing".
    await tester.pumpWidget(
      host(const KidShell(childName: 'Ada', childId: null)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Progress'));
    await tester.pump();

    // Still on Today — the tap is a no-op while childId is null.
    expect(find.text('Hi, Ada'), findsOneWidget);
  });

  testWidgets('renders without an unpair handler (no settings gear)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const KidShell(childName: 'Ada', childId: 'child-1')),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
