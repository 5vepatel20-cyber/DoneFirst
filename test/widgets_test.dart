import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:donefirst/widgets/empty_state.dart';

void main() {
  group('EmptyState', () {
    testWidgets('renders icon, title, and subtitle', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: LucideIcons.history,
            title: 'No sessions yet',
            subtitle: 'Complete homework to see your history',
          ),
        ),
      ));
      expect(find.byIcon(LucideIcons.history), findsOneWidget);
      expect(find.text('No sessions yet'), findsOneWidget);
      expect(find.text('Complete homework to see your history'), findsOneWidget);
    });

    testWidgets('renders without subtitle', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: const EmptyState(
            icon: LucideIcons.check,
            title: 'All done!',
          ),
        ),
      ));
      expect(find.byIcon(LucideIcons.check), findsOneWidget);
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
