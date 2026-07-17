import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_theme.dart';

/// Shown when the realtime subscription is healthy and there's no
/// active session for this kid. Tells the kid they're free to use
/// their apps. Asks a parent to start a lock if they want one.
class UnlockedScreen extends StatelessWidget {
  final String childName;
  const UnlockedScreen({super.key, required this.childName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.kidBg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: AppColors.okFill,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.check,
                    size: 56,
                    color: AppColors.ok,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'All clear, $childName',
                  textAlign: TextAlign.center,
                  style: AppText.title(size: 26),
                ),
                const SizedBox(height: 12),
                Text(
                  "You're free to use your apps. Ask a parent "
                  'to start a homework lock when you need '
                  'some quiet time to focus.',
                  textAlign: TextAlign.center,
                  style: AppText.bodySecondary(size: 15),
                ),
                const SizedBox(height: 36),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.kidLine),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.sparkles,
                        size: 16,
                        color: AppColors.grass,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Nice work staying focused',
                        style: AppText.body(color: AppColors.kidInk, size: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
