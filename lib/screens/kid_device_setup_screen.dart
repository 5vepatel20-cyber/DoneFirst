import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_theme.dart';

/// Walk-through for getting a kid's phone ready to enforce locks.
///
/// The single-app refactor means the parent already has the kid
/// APK installed on the kid's device — we don't need to walk
/// them through the Play Store. What we *do* need to walk them
/// through is the Android-specific setup that the OS requires
/// before the kid app can actually take over the screen:
///   1. The AccessibilityService prompt the kid app shows on first
///      launch (grants "Usage Access" + "Draw over other apps").
///   2. The one-time `adb shell dpm set-device-owner` command that
///      promotes the kid app to device-owner so the OS lets it
///      call `startLockTask()`.
///
/// Step (1) is in-app: the kid app will surface a banner with a
/// "Grant" button. Step (2) is what this screen covers.
///
/// Reachable from:
///   • KidDevicePairingScreen ("How to set up the kid's device")
///   • Help FAQ #1 ("… see the in-app setup guide")
class KidDeviceSetupScreen extends StatelessWidget {
  /// The kid-app applicationId. Must match
/// android/app/build.gradle.kts' `applicationId`. Hardcoded
  /// here because the kid app is a sibling Flutter project, not
  /// a packaged dependency of the parent — Dart has no way to
  /// read the kid app's package name at runtime.
  static const String kidAppPackage = 'com.donefirst.kid';

  /// The canonical one-line ADB command that promotes the kid app
  /// to device owner. Exposed as a static so the `_AdbCommandBox`
  /// (which can't see instance state — it's a separate
  /// `StatelessWidget` constructed inside the build method) doesn't
  /// have to walk the tree with `findAncestorWidgetOfExactType`.
  static const String adbCommand =
      'adb shell dpm set-device-owner '
      '$kidAppPackage/.KidDeviceAdminReceiver';

  const KidDeviceSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text('Kid device setup'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          const _StepCard(
            number: 1,
            icon: LucideIcons.download,
            title: 'Install DoneFirst on the kid’s phone',
            body:
                'Get the latest APK from the parent app’s onboarding or '
                'sideload the same build that the parent installed. The '
                'kid app is the same codebase but with the device-owner '
                'and accessibility permissions built in.',
          ),
          const _StepCard(
            number: 2,
            icon: LucideIcons.user,
            title: 'Open DoneFirst and choose “Kid”',
            body:
                'On the kid’s phone, launch DoneFirst. Pick “Kid” at the '
                'role-select screen and tap “I have a pairing code”. You '
                'don’t need a password for the kid account.',
          ),
          const _StepCard(
            number: 3,
            icon: LucideIcons.shieldCheck,
            title: 'Grant accessibility when prompted',
            body:
                'The kid app immediately asks for Android’s '
                'AccessibilityService permission — this is what lets it '
                'detect when other apps open and block them during a '
                'lock. Tap the system settings link, find DoneFirst, and '
                'toggle on. The kid app pops you back to itself once '
                'permission is granted.',
          ),
          const _StepCard(
            number: 4,
            icon: LucideIcons.terminal,
            title: 'Promote to device owner (one-time)',
            body:
                'Connect the kid phone to a computer with ADB installed '
                'and run the command below. You only need to do this '
                'once per device — it survives app updates and reboots. '
                'If the device already has another admin app installed, '
                'remove it first; Android only allows one device owner.',
            commandSlot: _AdbCommandBox(),
          ),
          const _StepCard(
            number: 5,
            icon: LucideIcons.keyRound,
            title: 'Pair the device from the parent app',
            body:
                'Back on your phone, open Settings → Kid devices, tap '
                'your child’s name, and read the 6-digit code aloud. '
                'Type it into the kid app — the device shows up in the '
                'paired-devices list within a few seconds.',
          ),
          const _StepCard(
            number: 6,
            icon: LucideIcons.checkCheck,
            title: 'Verify it worked',
            body:
                'Lock a quick 5-minute session from the dashboard. The '
                'kid phone should immediately switch to the lock screen '
                'and the home button should stop working. If it doesn’t, '
                'check the kid device status chip on the lock-active '
                'screen — it’ll tell you whether the device is online '
                'or still being set up.',
          ),
          const SizedBox(height: 24),
          const _Footnote(),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final int number;
  final IconData icon;
  final String title;
  final String body;
  final Widget? commandSlot;

  const _StepCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
    this.commandSlot,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.hair2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.forest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '$number',
                      style: AppText.cardHeader(
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(icon, size: 18, color: AppColors.forest),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: AppText.cardHeader(size: 15)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: AppText.body(size: 13.5),
            ),
            if (commandSlot != null) ...[
              const SizedBox(height: 12),
              commandSlot!,
            ],
          ],
        ),
      ),
    );
  }
}

class _AdbCommandBox extends StatelessWidget {
  const _AdbCommandBox();

  @override
  Widget build(BuildContext context) {
    // Take the command from the screen's static constant directly.
    // The previous version walked the tree with
    // `findAncestorWidgetOfExactType<KidDeviceSetupScreen>()` to
    // reach the screen's instance `_adbCommand` getter, plus a
    // duplicate hardcoded fallback in case the lookup returned
    // null. Both are unnecessary now that the command lives on the
    // screen class as a `static const` — every call site here
    // resolves to the same canonical string, and a future rename
    // of `kidAppPackage` only needs to happen in one place.
    const cmd = KidDeviceSetupScreen.adbCommand;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.deep,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              cmd,
              style: AppText.body(
                color: Colors.white,
                size: 12.5,
              ).copyWith(
                fontFamily: 'monospace',
                letterSpacing: 0.2,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(
              LucideIcons.copy,
              size: 16,
              color: Colors.white,
            ),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: cmd));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Command copied')),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warnFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warnBd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            LucideIcons.info,
            size: 16,
            color: AppColors.warn,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'A determined kid with USB debugging enabled can run '
              '`adb shell dpm remove-active-admin` and exit the lock. '
              'The device-owner model + AccessibilityService make this '
              'harder than the old parent-side blocks, but it isn’t '
              'tamper-proof. We treat this as a v1 trade-off and plan '
              'harder anti-tamper steps in a later release.',
              style: AppText.bodySecondary(size: 12),
            ),
          ),
        ],
      ),
    );
  }
}