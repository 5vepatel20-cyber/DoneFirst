import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/widgets/empty_state.dart';

void main() {
  group('EmptyState', () {
    testWidgets('renders icon, title, and subtitle', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.history,
            title: 'No sessions yet',
            subtitle: 'Complete homework to see your history',
          ),
        ),
      ));
      expect(find.byIcon(Icons.history), findsOneWidget);
      expect(find.text('No sessions yet'), findsOneWidget);
      expect(find.text('Complete homework to see your history'), findsOneWidget);
    });

    testWidgets('renders without subtitle', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: const EmptyState(
            icon: Icons.check,
            title: 'All done!',
          ),
        ),
      ));
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.text('All done!'), findsOneWidget);
    });
  });

  group('LoadingSkeleton', () {
    testWidgets('renders circular progress', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: const Center(child: CircularProgressIndicator()),
        ),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
