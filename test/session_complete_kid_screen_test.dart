import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:donefirst/screens/session_complete_kid_screen.dart';

/// Tests for the kid-side session-complete screen. Render-only:
/// the route is pushed by kid_home_screen when its realtime
/// subscription reports an ended session, and pops on tap. No
/// service calls, no global state — just widgets + a Navigator
/// to verify the back button pops correctly.
void main() {
  testWidgets('renders title, body, stat pills, and Back-to-home CTA',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SessionCompleteKidScreen(
        childName: 'Aarav',
        tasksCompleted: 4,
        streakDays: 6,
        minutesStudied: 45,
      ),
    ));
    // Pump the entry animation to its end so confetti / ring
    // painters stop repainting — otherwise the test sees a
    // constant stream of pending frames.
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('All done!'), findsOneWidget);
    expect(find.text('Your apps are unlocked'), findsOneWidget);
    expect(find.text('Back to home'), findsOneWidget);
    // Two stat pills with their labels.
    expect(find.text('Studied'), findsOneWidget);
    expect(find.text('Streak'), findsOneWidget);
    // 45 min renders as "45 min" (under 60 min path).
    expect(find.text('45 min'), findsOneWidget);
    // 6-day streak uses the plural path.
    expect(find.text('6 days'), findsOneWidget);
  });

  testWidgets('formats minutes over 60 with the h/m shape', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SessionCompleteKidScreen(
        childName: 'Aarav',
        tasksCompleted: 0,
        streakDays: 0,
        minutesStudied: 75,
      ),
    ));
    await tester.pump(const Duration(seconds: 2));

    // 75 minutes → "1h 15m". Verifies the non-zero-remainder branch.
    expect(find.text('1h 15m'), findsOneWidget);
  });

  testWidgets('singular "1 day" for one-day streak', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SessionCompleteKidScreen(
        childName: 'Aarav',
        tasksCompleted: 0,
        streakDays: 1,
        minutesStudied: 0,
      ),
    ));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('1 day'), findsOneWidget);
  });

  testWidgets('uses lucide timer + flame icons (no emoji)', (tester) async {
    // The handoff explicitly bans emoji in the kid app. Verify
    // both stat pills use line icons so the visual survives a
    // font-fallback review.
    await tester.pumpWidget(MaterialApp(
      home: SessionCompleteKidScreen(
        childName: 'Aarav',
        tasksCompleted: 1,
        streakDays: 1,
        minutesStudied: 30,
      ),
    ));
    await tester.pump(const Duration(seconds: 2));

    expect(find.byIcon(LucideIcons.timer), findsOneWidget);
    expect(find.byIcon(LucideIcons.flame), findsOneWidget);
    // No raw emoji: 🎉 / 🔥 would slip past `findsByType(Icon)`
    // but would still be present as Text widgets.
    expect(find.text('🎉'), findsNothing);
    expect(find.text('🔥'), findsNothing);
  });

  testWidgets('Back-to-home button pops the route', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (rootContext) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(rootContext).push(
                MaterialPageRoute(
                  builder: (_) => SessionCompleteKidScreen(
                    childName: 'Aarav',
                    tasksCompleted: 1,
                    streakDays: 0,
                    minutesStudied: 30,
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Tap the celebration's back CTA and verify we returned to
    // the launching screen.
    await tester.tap(find.text('Back to home'));
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Back to home'), findsNothing);
  });
}