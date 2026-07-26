import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:donefirst/screens/kid/pairing_screen.dart';
import 'package:donefirst/services/kid_auth_service.dart';
import 'package:donefirst/supabase_config.dart';

/// The pairing screen used to ship its own on-screen number pad —
/// twelve hand-drawn key tiles driving a hidden controller. On iOS
/// that means reimplementing the system keypad badly: no paste, no
/// dictation, no accessibility affordances, and a layout that has to
/// be maintained against every screen size by hand.
///
/// It's now a real TextField behind the six code cells, so the
/// platform supplies its own numeric keyboard.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    try {
      await initSupabase();
    } catch (_) {
      // Offline is fine — KidAuthService only needs Supabase.instance
      // to exist in order to construct.
    }
  });

  Future<void> pumpPairing(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: PairingScreen(authService: KidAuthService())),
    );
    await tester.pump();
  }

  testWidgets('entry goes through a real text field, not custom keys', (
    tester,
  ) async {
    await pumpPairing(tester);

    final field = find.byType(TextField);
    expect(field, findsOneWidget);

    final widget = tester.widget<TextField>(field);
    expect(
      widget.keyboardType,
      TextInputType.number,
      reason: 'iOS should show its numeric keypad',
    );
    expect(widget.autofocus, isTrue, reason: 'keyboard comes up on arrival');
  });

  testWidgets('no hand-rolled digit keys remain on screen', (tester) async {
    await pumpPairing(tester);

    // The old pad rendered every digit as its own tappable tile. An
    // empty code means none of them should be painted anywhere.
    for (final digit in ['1', '5', '9', '0']) {
      expect(
        find.text(digit),
        findsNothing,
        reason: 'digit $digit belongs to the platform keyboard now',
      );
    }
  });

  testWidgets('typed digits fill the code cells', (tester) async {
    await pumpPairing(tester);

    await tester.enterText(find.byType(TextField), '4213');
    await tester.pump();

    for (final digit in ['4', '2', '1', '3']) {
      expect(find.text(digit), findsOneWidget);
    }
  });

  testWidgets('non-digits are rejected by the input formatter', (tester) async {
    await pumpPairing(tester);

    final widget = tester.widget<TextField>(find.byType(TextField));
    expect(
      widget.inputFormatters,
      contains(isA<FilteringTextInputFormatter>()),
    );
    expect(
      widget.inputFormatters,
      contains(isA<LengthLimitingTextInputFormatter>()),
    );
  });
}
