import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../screens/kid_device_setup_screen.dart';
import '../theme/app_theme.dart';

/// Compact hint card surfaced on the parent dashboard when the
/// family has children but no paired kid device for any of them.
/// Tap → opens the kid-app setup screen (the same one PIN-gated
/// in Settings → Devices), so the parent can either read the
/// install steps or jump straight to pairing.
///
/// Kept intentionally small (one icon + headline + subhead +
/// action) so it doesn't compete with the schedule-card hero or
/// the per-child cards below it.
class KidDeviceSetupHintCard extends StatelessWidget {
  const KidDeviceSetupHintCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.warnFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.warnBd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warn.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.iconTile),
              ),
              child: const Icon(
                LucideIcons.smartphone,
                size: 18,
                color: AppColors.warn,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Lock apps on your kid\'s phone',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Pair the DoneFirst Kid app to enforce the lock '
                    'on the device they actually use.',
                    style: AppText.bodySecondary(size: 12.5),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _openSetup(context),
                        icon: const Icon(LucideIcons.bookOpen, size: 14),
                        label: const Text('Setup guide'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.ink,
                          side: const BorderSide(color: AppColors.warnBd),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          textStyle: AppText.button(color: AppColors.ink),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSetup(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const KidDeviceSetupScreen()),
    );
  }
}
