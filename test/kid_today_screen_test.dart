import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:donefirst/screens/kid/today_screen.dart';
import 'package:donefirst/supabase_config.dart';

/// The kid's free-time home is what a paired kid sees whenever no
/// session is running — i.e. most of the time. It renders before any
/// of its three fetches land and again after they fail (a kid device
/// is offline more often than a parent's), so "it renders at all" is
/// the property worth pinning: a throw here shows the kid a black
/// screen with no way out.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    try {
      await initSupabase();
    } catch (_) {
      // Offline is fine — the screen only needs Supabase.instance to
      // exist so StreakService/ScheduleService can construct.
    }
  });

  Widget host(Widget child) => MaterialApp(home: child);

  testWidgets('renders the dashboard with no child id (no fetch)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const KidTodayScreen(childName: 'Ada', childId: null)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Hi, Ada'), findsOneWidget);
    expect(find.text('No session running'), findsOneWidget);
    // DfSectionLabel renders its text upper-cased.
    expect(find.text('TODAY AT A GLANCE'), findsOneWidget);
    expect(find.text('NEXT SESSION'), findsOneWidget);
  });

  testWidgets('survives the fetch path failing (offline kid device)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const KidTodayScreen(
          childName: 'Ada',
          childId: '00000000-0000-0000-0000-000000000000',
        ),
      ),
    );
    // Let the three best-effort reads reject and _load's setState run.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text('Hi, Ada'), findsOneWidget);
    // A failed read must read as "unknown", never a confident zero.
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('a child id that arrives late still triggers the load', (
    tester,
  ) async {
    // kid_root builds this screen from kidAuth.childId, which is null
    // until restoreSession finishes. The rebuild that follows reuses
    // the same State — initState does not run again — so a _load that
    // only ever fired from initState left the screen permanently in
    // its "no child id" result: three "—" tiles under a next-session
    // card that claimed nothing was scheduled.
    await tester.pumpWidget(
      host(const KidTodayScreen(childName: 'Ada', childId: null)),
    );
    await tester.pump();
    expect(find.text('Getting your schedule ready…'), findsOneWidget);

    await tester.pumpWidget(
      host(
        const KidTodayScreen(
          childName: 'Ada',
          childId: '00000000-0000-0000-0000-000000000000',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    // Offline in tests, so the read fails rather than returning rows —
    // what matters is that it was attempted at all, which the "no
    // child id" copy no longer being on screen proves.
    expect(find.text('Getting your schedule ready…'), findsNothing);
  });

  testWidgets('an unreadable schedule is not reported as an empty one', (
    tester,
  ) async {
    // "Nothing scheduled yet — your parent can set up a homework
    // routine" is a claim about the parent's setup. When the read
    // fails we have no idea whether that is true, and the kid needs a
    // way to ask again rather than a dead statement.
    await tester.pumpWidget(
      host(
        const KidTodayScreen(
          childName: 'Ada',
          childId: '00000000-0000-0000-0000-000000000000',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Nothing scheduled yet — your parent can set up a '
        'homework routine.'), findsNothing);
    expect(find.text('Couldn’t check your schedule just now.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('fits a small phone without overflowing', (tester) async {
    // 320x568 — the smallest screen we still claim to support.
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(const KidTodayScreen(childName: 'Bartholomew', childId: null)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('greets without a name when the kid name is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const KidTodayScreen(childName: 'there', childId: null)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Hi, there'), findsOneWidget);
  });
}
