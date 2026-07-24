import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';

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
      appBar: AppBar(title: const Text('Kid device setup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          12,
          AppSpacing.screenPadding,
          32,
        ),
        children: [
          Text('Set up the kid’s device', style: AppText.screenTitle()),
          const SizedBox(height: 6),
          Text(
            'Five quick steps — including the one-time ADB command that '
            'lets DoneFirst hold the lock screen.',
            style: AppText.bodySecondary(size: 13.5),
          ),
          const SizedBox(height: AppSpacing.blockGap),
          const _StepCard(
            number: 1,
            icon: LucideIcons.download,
            title: 'Install DoneFirst on the kid’s phone',
            body: 'Same build the parent installed.',
          ),
          const _StepCard(
            number: 2,
            icon: LucideIcons.user,
            title: 'Open it and choose “Kid”',
            body: 'Tap “I have a pairing code.” No password needed.',
          ),
          const _StepCard(
            number: 3,
            icon: LucideIcons.shieldCheck,
            title: 'Grant accessibility when asked',
            body: 'Lets the app detect & pause other apps in a lock.',
          ),
          const _StepCard(
            number: 4,
            icon: LucideIcons.terminal,
            title: 'Promote to device owner (one-time)',
            body: 'Run this once over ADB — survives reboots.',
            commandSlot: _AdbCommandBox(),
          ),
          const _StepCard(
            number: 5,
            icon: LucideIcons.checkCheck,
            title: 'Enter the pairing code, then test',
            body:
                'Lock a 5-min session — the phone should switch to '
                'the lock screen.',
          ),
          const SizedBox(height: 20),
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
      child: DfCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  child: Center(
                    child: Text(
                      '$number',
                      style: AppText.cardHeader(color: Colors.white, size: 15),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(icon, size: 18, color: AppColors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: AppText.cardHeader(size: 15)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(body, style: AppText.bodySecondary(size: 13.5)),
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
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppRadius.tile),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              cmd,
              style: AppText.code(
                size: 12.5,
                color: Colors.white,
              ).copyWith(letterSpacing: 0, height: 1.4),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(LucideIcons.copy, size: 16, color: Colors.white),
            onPressed: () async {
              await Clipboard.setData(const ClipboardData(text: cmd));
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Command copied')));
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
    return DfCard(
      color: AppColors.amberTint,
      borderColor: AppColors.amberTint2,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.info, size: 16, color: AppColors.amberDeep),
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
