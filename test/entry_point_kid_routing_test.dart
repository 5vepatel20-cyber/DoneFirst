import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:donefirst/main.dart';
import 'package:donefirst/screens/kid/kid_root.dart';
import 'package:donefirst/screens/role_select_screen.dart';
import 'package:donefirst/supabase_config.dart';

/// EntryPoint decides the app's very first route. It used to decide
/// it from `Supabase.auth.currentUser` alone — and a kid device's
/// identity does not live there.
///
/// A paired kid keeps its tokens in SharedPreferences and rebuilds
/// the Supabase session from them later, in KidRoot._bootstrap. Until
/// that lands — and `Supabase.initialize` gives up recovering its
/// stored session after 10s on web — `currentUser` is null on a
/// device that is fully paired and, on Android, actively locked. The
/// old code sent those launches to "Who's going to use it?", offering
/// a locked-down kid tablet the option to set itself up as the
/// parent's phone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // Supabase.initialize opens its own SharedPreferences-backed
    // storage, so the mock has to exist before it runs. Each test
    // then replaces the values with the case it cares about.
    SharedPreferences.setMockInitialValues({});
    try {
      await initSupabase();
    } catch (_) {
      // Offline is fine — with no session, currentUser is null, which
      // is exactly the branch under test.
    }
  });

  testWidgets('a device with persisted kid tokens boots into the kid app', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_done': true,
      'kid_access_token': 'header.payload.signature',
      'kid_refresh_token': 'refresh-token',
    });

    await tester.pumpWidget(const DoneFirstApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(KidRoot), findsOneWidget);
    expect(
      find.byType(RoleSelectScreen),
      findsNothing,
      reason: 'this device already belongs to a kid',
    );

    // KidRoot._bootstrap arms a ceiling timer. Unmount, then let it
    // fire, so teardown doesn't report it as leaked.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 41));
  });

  testWidgets('a device with no kid tokens still reaches the chooser', (
    tester,
  ) async {
    // The other half of the branch: without tokens there is nothing to
    // restore, and the chooser is the correct destination. A fix that
    // routed everyone to the kid app would strand new parents.
    SharedPreferences.setMockInitialValues({'onboarding_done': true});

    await tester.pumpWidget(const DoneFirstApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(RoleSelectScreen), findsOneWidget);
    expect(find.byType(KidRoot), findsNothing);
  });

  testWidgets('a paired kid still boots into the kid app when auth throws', (
    tester,
  ) async {
    // The other way this screen is reached: _resolveRoute threw
    // outright — which is what happens when initSupabase() times out
    // in main() and every Supabase.instance access starts throwing.
    // The error fallback used to send everyone to the chooser
    // unconditionally.
    SharedPreferences.setMockInitialValues({
      'onboarding_done': true,
      'kid_access_token': 'header.payload.signature',
      'kid_refresh_token': 'refresh-token',
    });

    await tester.pumpWidget(const DoneFirstApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(RoleSelectScreen), findsNothing);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 41));
  });

  testWidgets('a half-written pairing is not treated as paired', (
    tester,
  ) async {
    // signOut clears both keys; a launch that catches it mid-write
    // must not claim the device is paired, because KidRoot would then
    // hide the pairing screen with no identity to work from.
    SharedPreferences.setMockInitialValues({
      'onboarding_done': true,
      'kid_access_token': 'header.payload.signature',
    });

    await tester.pumpWidget(const DoneFirstApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(RoleSelectScreen), findsOneWidget);
  });
}
