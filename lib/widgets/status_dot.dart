import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 7px colored dot paired with a 12px ink2 label. Used in the
/// dashboard per-child row to show idle / locked / paused status.
///
/// Common variants:
///   - locked → AppColors.warnDot (amber)
///   - idle   → AppColors.sage (green)
///   - ended  → AppColors.muted
class StatusDot extends StatelessWidget {
  final Color color;
  final String label;
  final double dotSize;

  const StatusDot({
    super.key,
    required this.color,
    required this.label,
    this.dotSize = 7,
  });

  /// Convenience for "locked" state.
  const StatusDot.locked({super.key, required this.label})
      : color = AppColors.warnDot,
        dotSize = 7;

  /// Convenience for "idle / no session" state.
  const StatusDot.idle({super.key, required this.label})
      : color = AppColors.sage,
        dotSize = 7;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppText.bodySecondary(),
        ),
      ],
    );
  }
}