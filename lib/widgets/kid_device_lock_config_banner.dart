import 'package:flutter/material.dart';
import 'package:donefirst/theme/app_theme.dart';

/// Pre-flight warning rendered above the Start button on
/// `lock_config_screen` when the chosen child has no paired,
/// non-revoked kid device. Mirrors the same pattern as
/// `lock_active_screen.dart`'s no-device banner — but here it's
/// shown before the parent commits to a lock, when they can still
/// back out and pair without disrupting a running session.
///
/// Extracted from the screen so it can be tested without dragging
/// in the lock_config_screen's full Supabase service graph. The
/// contract is purely visual + interaction: show the banner copy
/// for [childName] + a Pair now [onPair] callback.
class KidDeviceLockConfigBanner extends StatelessWidget {
  final String childName;
  final VoidCallback onPair;

  const KidDeviceLockConfigBanner({
    super.key,
    required this.childName,
    required this.onPair,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.warnFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.warnBd, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.warn,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Pair $childName's phone first, or this lock "
                "won't be enforced on the kid's device.",
                style: AppText.body(size: 13, color: AppColors.ink),
              ),
            ),
            TextButton(
              onPressed: onPair,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.ink,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Pair now',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
