import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:donefirst/screens/session_complete_kid_screen.dart';

/// Tests for the kid-side session-complete screen (premium "Unlocked ✦"
/// celebration). Render-only: the route is pushed by kid_home_screen
/// when its realtime subscription reports an ended session, and pops on
/// tap. No service calls — just widgets + a Navigator to verify the CTA
/// pops correctly.
void main() {
  testWidgets('renders headline, body, stats, and the done CTA', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SessionCompleteKidScreen(
          childName: 'Aarav',
          tasksCompleted: 4,
          streakDays: 6,
          minutesStudied: 45,
        ),
      ),
    );
    // Pump the entry animation to its end so the ring / confetti
    // painters stop repainting.
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Approved.'), findsOneWidget);
    expect(find.text("You're free."), findsOneWidget);
    expect(find.text('Apps are unlocked. Nice work today.'), findsOneWidget);
    expect(find.text('Done — open my apps'), findsOneWidget);
    // Stats: 45 min renders as "45m" (under-60 path); streak + tasks
    // captions present.
    expect(find.text('45m'), findsOneWidget);
    expect(find.text('day streak'), findsOneWidget);
    expect(find.text('tasks done'), findsOneWidget);
  });

  testWidgets('formats minutes over 60 with the h/m shape', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SessionCompleteKidScreen(
          childName: 'Aarav',
          tasksCompleted: 0,
          streakDays: 0,
          minutesStudied: 75,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    // 75 minutes → "1h 15m". Verifies the non-zero-remainder branch.
    expect(find.text('1h 15m'), findsOneWidget);
  });

  testWidgets('singular "task done" for a single task', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SessionCompleteKidScreen(
          childName: 'Aarav',
          tasksCompleted: 1,
          streakDays: 1,
          minutesStudied: 0,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('task done'), findsOneWidget);
  });

  testWidgets('uses a lucide flame icon (no emoji)', (tester) async {
    // The handoff explicitly bans emoji in the kid app. Verify the
    // streak stat uses a line icon so the visual survives a
    // font-fallback review.
    await tester.pumpWidget(
      MaterialApp(
        home: SessionCompleteKidScreen(
          childName: 'Aarav',
          tasksCompleted: 1,
          streakDays: 1,
          minutesStudied: 30,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(find.byIcon(LucideIcons.flame), findsOneWidget);
    // No raw emoji: 🎉 / 🔥 would slip past a byType(Icon) finder
    // but would still be present as Text widgets.
    expect(find.text('🎉'), findsNothing);
    expect(find.text('🔥'), findsNothing);
  });

  testWidgets('done button pops the route', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
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
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Tap the celebration's done CTA and verify we returned to the
    // launching screen.
    await tester.tap(find.text('Done — open my apps'));
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Done — open my apps'), findsNothing);
  });
}
