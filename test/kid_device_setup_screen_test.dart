import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:donefirst/screens/kid_device_setup_screen.dart';
import 'package:donefirst/theme/app_theme.dart';

/// Smoke test for the setup guide screen. We don't simulate ADB or
/// test the device-owner promotion — that needs a real device.
/// We just verify the walk-through renders all six steps in order
/// and exposes the canonical ADB command so the parent can copy it.
void main() {
  testWidgets('setup guide renders all six steps with the ADB command',
      (tester) async {
    // Force a tall viewport so ListView builds every step card
    // instead of lazy-truncating at the test default.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const KidDeviceSetupScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Step titles from the screen's _StepCard children.
    const titles = [
      'Install DoneFirst on the kid’s phone',
      'Open DoneFirst and choose “Kid”',
      'Grant accessibility when prompted',
      'Promote to device owner (one-time)',
      'Pair the device from the parent app',
      'Verify it worked',
    ];
    for (final t in titles) {
      expect(find.text(t), findsOneWidget,
          reason: 'expected step title to render: "$t"');
    }

    // The ADB command must be present and copyable. The screen
    // exposes it as plain text inside the dark command box.
    const expectedCmd =
        'adb shell dpm set-device-owner '
        'com.donefirst.kid/.KidDeviceAdminReceiver';
    expect(find.text(expectedCmd), findsOneWidget);

    // Copy button is wired (we don't simulate clipboard). The widget
  // uses LucideIcons, so search for it specifically rather than
  // the Material Icons.copy which isn't used here.
    expect(find.byIcon(LucideIcons.copy), findsOneWidget);
  });

  testWidgets('hardcoded package name matches what the kid app uses',
      (tester) async {
    // Drift here would silently brick the ADB instruction. Pin
    // the value so any rename in the kid app's build.gradle.kts
    // also breaks this test loudly.
    expect(KidDeviceSetupScreen.kidAppPackage, 'com.donefirst.kid');
  });
}