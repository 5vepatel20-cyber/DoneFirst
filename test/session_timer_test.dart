import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/widgets/session_timer.dart';

void main() {
  group('SessionTimer', () {
    testWidgets('renders without error', (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SessionTimer(
            sessionStart: now.subtract(const Duration(hours: 1)),
            durationMinutes: 120,
          ),
        ),
      ));
      // Widget renders - timer may tick during test
      expect(find.byType(SessionTimer), findsOneWidget);
    });

    testWidgets('shows paused state', (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionTimer(
              sessionStart: now.subtract(const Duration(minutes: 30)),
              durationMinutes: 60,
              paused: true,
            ),
          ),
        ),
      );
      expect(find.text('Paused'), findsOneWidget);
    });

    testWidgets('accepts min and auto-lift values', (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionTimer(
              sessionStart: now.subtract(const Duration(minutes: 45)),
              durationMinutes: 60,
              minUnlockMinutes: 60,
              autoLiftMinutes: 120,
            ),
          ),
        ),
      );
      // Widget should render without error
      expect(find.byType(SessionTimer), findsOneWidget);
    });
  });
}
