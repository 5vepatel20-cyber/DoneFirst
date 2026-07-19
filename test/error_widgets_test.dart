import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:donefirst/widgets/error_banner.dart';

void main() {
  group('ErrorBanner', () {
    testWidgets('shows message', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ErrorBanner(message: 'Something went wrong'),
        ),
      ));
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.byIcon(LucideIcons.alertCircle), findsOneWidget);
    });

    testWidgets('shows retry button', (tester) async {
      var retried = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ErrorBanner(
            message: 'Failed',
            onRetry: () => retried = true,
          ),
        ),
      ));
      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('dismiss button clears error', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ErrorBanner(
            message: 'Error',
            onDismiss: () => dismissed = true,
          ),
        ),
      ));
      await tester.tap(find.byIcon(LucideIcons.x));
      expect(dismissed, isTrue);
    });
  });

  group('RetryWidget', () {
    testWidgets('shows message and retry button', (tester) async {
      var retried = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RetryWidget(
            message: 'Could not load data',
            onRetry: () => retried = true,
          ),
        ),
      ));
      expect(find.text('Could not load data'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
      await tester.tap(find.text('Try Again'));
      expect(retried, isTrue);
    });
  });

  group('OfflineBanner', () {
    testWidgets('shows when offline', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OfflineBanner(isOffline: true),
        ),
      ));
      expect(find.text('No internet connection'), findsOneWidget);
    });

    testWidgets('hides when online', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OfflineBanner(isOffline: false),
        ),
      ));
      expect(find.text('No internet connection'), findsNothing);
    });
  });
}
