// Tests for help_screen.dart — verifies the FAQ renders all categories,
// the support card is shown, and expanding a tile reveals the answer.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/screens/help_screen.dart';
import 'package:donefirst/screens/upgrade_screen.dart';
import 'package:donefirst/theme/app_theme.dart';

void main() {
  Future<void> _pump(WidgetTester tester) {
    // Use a tall surface so the lazy ListView builds every category
    // — otherwise off-screen categories can't be found in the tree.
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    return tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        ),
        home: const HelpScreen(),
      ),
    );
  }

  testWidgets('renders AppBar with title', (tester) async {
    await _pump(tester);
    expect(find.text('Help & Support'), findsOneWidget);
  });

  testWidgets('shows support contact card', (tester) async {
    await _pump(tester);
    expect(find.text('Need more help?'), findsOneWidget);
    expect(find.textContaining('support@donefirst.app'), findsOneWidget);
  });

  testWidgets('renders all five category headings', (tester) async {
    await _pump(tester);
    expect(find.text('Getting started'), findsOneWidget);
    expect(find.text('Proofs & AI verification'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Account & privacy'), findsOneWidget);
    expect(find.text('Billing & plans'), findsOneWidget);
  });

  testWidgets('questions are visible but answers are collapsed by default',
      (tester) async {
    await _pump(tester);
    // A representative question is visible.
    expect(
      find.text("How do I set up my kid's device?"),
      findsOneWidget,
    );
    // The answer text is not yet visible — it's inside a collapsed tile.
    expect(
      find.textContaining(
        'Install DoneFirst on both your phone',
      ),
      findsNothing,
    );
  });

  testWidgets('tapping a question expands it to show the answer',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text("How do I set up my kid's device?"));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Install DoneFirst on both your phone'),
      findsOneWidget,
    );
  });

  testWidgets('every FAQ question across every category is rendered',
      (tester) async {
    await _pump(tester);
    // A few specific anchors so a category accidentally being
    // dropped would break this test, not silently ship.
    expect(find.text('Why is "needs_review" showing up so often?'),
        findsOneWidget);
    expect(find.text("I'm not getting notifications."), findsOneWidget);
    expect(find.text('How do I export or delete my data?'), findsOneWidget);
    expect(find.text('How many free sessions do I get per month?'),
        findsOneWidget);
  });

  testWidgets('free-sessions FAQ answer matches UpgradeScreen.freeLimit',
      (tester) async {
    // Defensive: help used to hardcode '10' while UpgradeScreen
    // actually said 3, so a parent who read help would expect 10 but
    // hit 3. Now the answer interpolates UpgradeScreen.freeLimit
    // — if anyone flips the constant, the help text follows.
    await _pump(tester);
    await tester.tap(
      find.text('How many free sessions do I get per month?'),
    );
    await tester.pumpAndSettle();
    final expected = '${UpgradeScreen.freeLimit} sessions per parent account';
    expect(find.textContaining(expected), findsOneWidget);
  });
}