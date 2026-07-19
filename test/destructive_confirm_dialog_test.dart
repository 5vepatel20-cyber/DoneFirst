import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:donefirst/widgets/destructive_confirm_dialog.dart';

/// Widget tests for the destructive confirm dialog. The dialog is
/// shown via `DestructiveConfirmDialog.show(...)` which returns
/// `Future<bool>`. Each test pumps a tiny app shell that triggers
/// `.show()` and then waits on the returned future.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Pumps the dialog via the static helper and returns both the
  // tester and the pending future so callers can `await` it.
  Future<(WidgetTester, Future<bool>)> pump(
    WidgetTester tester, {
    required String title,
    required String description,
    required String confirmPhrase,
    String confirmButtonLabel = 'Delete',
    String? warningText,
    IconData? warningIcon,
  }) async {
    final completer = Completer<bool>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: TextButton(
              onPressed: () async {
                final r = await DestructiveConfirmDialog.show(
                  ctx,
                  title: title,
                  description: description,
                  confirmPhrase: confirmPhrase,
                  confirmButtonLabel: confirmButtonLabel,
                  warningText: warningText,
                  warningIcon: warningIcon,
                );
                completer.complete(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return (tester, completer.future);
  }

  testWidgets('renders title, description, confirm label', (tester) async {
    final (_, pending) = await pump(
      tester,
      title: 'Delete Avery?',
      description: 'Body copy explaining consequences.',
      confirmPhrase: 'Avery',
    );

    expect(find.text('Delete Avery?'), findsOneWidget);
    expect(find.text('Body copy explaining consequences.'), findsOneWidget);
    expect(find.text('Type Avery to confirm:'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Avery'), findsOneWidget);

    // Cancel to settle the future so the test doesn't hang.
    await tester.tap(find.text('Cancel'));
    expect(await pending, isFalse);
  });

  testWidgets('Delete button is disabled until phrase matches', (tester) async {
    final (_, pending) = await pump(
      tester,
      title: 'Delete Avery?',
      description: 'Body.',
      confirmPhrase: 'Avery',
    );

    // The Delete (FilledButton) is in the actions row. It starts
    // disabled because the field is empty.
    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNull,
        reason: 'confirm button must be disabled before phrase matches');

    // Wrong text → still disabled.
    await tester.enterText(find.byType(TextField), 'Av');
    await tester.pump();
    final btn2 = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn2.onPressed, isNull);

    // Correct text → enabled.
    await tester.enterText(find.byType(TextField), 'Avery');
    await tester.pump();
    final btn3 = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn3.onPressed, isNotNull);

    await tester.tap(find.text('Cancel'));
    expect(await pending, isFalse);
  });

  testWidgets('matches are case-insensitive via trim, exact match required',
      (tester) async {
    final (_, pending) = await pump(
      tester,
      title: 't',
      description: 'd',
      confirmPhrase: 'Avery',
    );

    // Surrounding whitespace doesn't count; exact case + spelling does.
    await tester.enterText(find.byType(TextField), '  Avery  ');
    await tester.pump();
    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNotNull);

    // Wrong case → still disabled.
    await tester.enterText(find.byType(TextField), 'avery');
    await tester.pump();
    final btn2 = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn2.onPressed, isNull);

    await tester.tap(find.text('Cancel'));
    expect(await pending, isFalse);
  });

  testWidgets('warning block renders only when warningText supplied',
      (tester) async {
    // No warning text → no warning block.
    await pump(
      tester,
      title: 't',
      description: 'd',
      confirmPhrase: 'Avery',
    );
    expect(find.byIcon(LucideIcons.alertTriangle), findsNothing);

    // Close the open dialog before opening the next one.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // With warningText → icon appears.
    final (_, pending) = await pump(
      tester,
      title: 't',
      description: 'd',
      confirmPhrase: 'Avery',
      warningText: 'A device is paired to this child.',
    );
    expect(find.byIcon(LucideIcons.alertTriangle), findsOneWidget);
    expect(find.text('A device is paired to this child.'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    expect(await pending, isFalse);
  });

  testWidgets('custom warningIcon overrides the default alertTriangle',
      (tester) async {
    final (_, pending) = await pump(
      tester,
      title: 't',
      description: 'd',
      confirmPhrase: 'Avery',
      warningText: 'Paired device warning',
      warningIcon: LucideIcons.shieldOff,
    );
    // The custom icon is present; the default alertTriangle is not.
    expect(find.byIcon(LucideIcons.shieldOff), findsOneWidget);
    expect(find.byIcon(LucideIcons.alertTriangle), findsNothing);

    await tester.tap(find.text('Cancel'));
    expect(await pending, isFalse);
  });

  testWidgets('Cancel returns false', (tester) async {
    final (_, pending) = await pump(
      tester,
      title: 't',
      description: 'd',
      confirmPhrase: 'Avery',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await pending, isFalse);
  });

  testWidgets('tapping Delete with matching phrase returns true',
      (tester) async {
    final (_, pending) = await pump(
      tester,
      title: 't',
      description: 'd',
      confirmPhrase: 'Avery',
      confirmButtonLabel: 'Delete forever',
    );
    await tester.enterText(find.byType(TextField), 'Avery');
    await tester.pump();
    await tester.tap(find.text('Delete forever'));
    await tester.pumpAndSettle();
    expect(await pending, isTrue);
  });

  testWidgets('submitting via keyboard returns true when phrase matches',
      (tester) async {
    final (_, pending) = await pump(
      tester,
      title: 't',
      description: 'd',
      confirmPhrase: 'Avery',
    );
    await tester.enterText(find.byType(TextField), 'Avery');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(await pending, isTrue);
  });

  testWidgets('submitting via keyboard does not pop when phrase does not match',
      (tester) async {
    final (_, pending) = await pump(
      tester,
      title: 't',
      description: 'd',
      confirmPhrase: 'Avery',
    );
    await tester.enterText(find.byType(TextField), 'Av');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    // Dialog is still mounted; the future hasn't completed.
    expect(find.text('Delete'), findsOneWidget);
    // Now cancel to settle.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await pending, isFalse);
  });
}
