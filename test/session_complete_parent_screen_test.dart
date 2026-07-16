import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:donefirst/screens/session_complete_parent_screen.dart';

/// Tests for the parent celebration screen. The screen is the
/// closing moment after `_unlock()` in lock_active_screen — the
/// parent sees it once, taps "Back to dashboard", and is done. It
/// has no data-fetching logic, just rendering + a callback, so the
/// tests focus on what shows up given a few stat permutations.
void main() {
  testWidgets('renders headline, child name in subtitle, all stat pills, and done CTA',
      (tester) async {
    var doneTaps = 0;
    await tester.pumpWidget(MaterialApp(
      home: SessionCompleteParentScreen(
        childName: 'Ada',
        minutesStudied: 45,
        tasksCompleted: 3,
        streakDays: 7,
        onDone: () => doneTaps++,
      ),
    ));
    // Pump the confetti animation to its end so it stops drawing
    // (the painter returns early at 1.0). Otherwise the test sees
    // AnimatedBuilder ticking frames.
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Homework complete'), findsOneWidget);
    expect(find.text('Ada is free to go'), findsOneWidget);
    expect(find.text('45 min'), findsOneWidget);
    expect(find.text('studied'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('tasks approved'), findsOneWidget);
    expect(find.text('7-day'), findsOneWidget);
    expect(find.text('streak'), findsOneWidget);
    expect(find.text('Back to dashboard'), findsOneWidget);

    // Stat pill icons.
    expect(find.byIcon(LucideIcons.clock), findsOneWidget);
    expect(find.byIcon(LucideIcons.checkCheck), findsOneWidget);
    expect(find.byIcon(LucideIcons.flame), findsOneWidget);
    expect(find.byIcon(LucideIcons.check), findsOneWidget); // ring center
    expect(find.byIcon(LucideIcons.arrowLeft), findsOneWidget); // done CTA

    await tester.tap(find.text('Back to dashboard'));
    expect(doneTaps, 1);
  });

  testWidgets('singular "task approved" copy when tasksCompleted is 1',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SessionCompleteParentScreen(
        childName: 'Ada',
        minutesStudied: 20,
        tasksCompleted: 1,
        streakDays: 2,
        onDone: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    expect(find.text('task approved'), findsOneWidget);
    expect(find.text('tasks approved'), findsNothing);
  });

  testWidgets('hides pills whose value is zero or negative', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SessionCompleteParentScreen(
        childName: '',
        minutesStudied: 0,
        tasksCompleted: 0,
        streakDays: 0,
        onDone: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Homework complete'), findsOneWidget);
    // No child name → fallback copy.
    expect(find.text('Apps are unlocked'), findsOneWidget);
    expect(find.text('Back to dashboard'), findsOneWidget);
    // No stat pills should render when all values are zero.
    expect(find.byIcon(LucideIcons.clock), findsNothing);
    expect(find.byIcon(LucideIcons.checkCheck), findsNothing);
    expect(find.byIcon(LucideIcons.flame), findsNothing);
  });

  testWidgets('shows only the pills whose value is non-zero', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SessionCompleteParentScreen(
        childName: 'Ada',
        minutesStudied: 30,
        tasksCompleted: 0,
        streakDays: 5,
        onDone: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('30 min'), findsOneWidget);
    expect(find.text('5-day'), findsOneWidget);
    // Tasks pill hidden because count is zero.
    expect(find.byIcon(LucideIcons.checkCheck), findsNothing);
  });
}
