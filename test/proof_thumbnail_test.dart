import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:donefirst/widgets/proof_thumbnail.dart';

void main() {
  group('ProofThumbnail', () {
    testWidgets('renders Image.network with the given url', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProofThumbnail(
              url: 'https://example.com/proof.jpg',
            ),
          ),
        ),
      );
      // The widget builds an Image.network internally. We can't
      // assert the image actually loaded (network calls fail in
      // widget tests), but we can verify the widget is on screen.
      expect(find.byType(ProofThumbnail), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('falls back to the placeholder on error', (tester) async {
      // NetworkImage is what Image.network uses. By feeding it a
      // definitely-broken URL, we drive the errorBuilder branch
      // and verify the placeholder text appears.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProofThumbnail(
              url:
                  'https://localhost:1/this-does-not-exist-and-cannot-resolve',
            ),
          ),
        ),
      );
      // Let the image fail.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Photo no longer available'), findsOneWidget);
      expect(find.byIcon(LucideIcons.imageOff), findsOneWidget);
    });
  });
}