import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:donefirst/theme/app_theme.dart';

/// Compact two-line status caption shown next to each child on
/// the parent dashboard. First line is the dot + label
/// ("Device online", "No device paired", …). Second line is the
/// "Last seen 3 min ago" caption — suppressed for "No device
/// paired" / "revoked" states where it isn't meaningful.
///
/// The "No device paired" state is the only one that fires
/// [onPair]; the other states are passive status indicators. The
/// CTA's purpose is to make the long-press-on-avatar pairing
/// affordance redundant — a parent who notices "no device
/// paired" can tap it directly.
///
/// Extracted from `parent_dashboard.dart` so it can be tested
/// without dragging in the dashboard's full Supabase service
/// graph. Pure rendering + interaction.
class KidDeviceStatusCaption extends StatelessWidget {
  /// 'online' | 'recent' | 'stale' | 'revoked' | null. null = no
  /// paired device at all.
  final String? status;
  final DateTime? lastSeenAt;
  final VoidCallback? onPair;

  const KidDeviceStatusCaption({
    super.key,
    required this.status,
    this.lastSeenAt,
    this.onPair,
  });

  @override
  Widget build(BuildContext context) {
    final (color, label) = _labelFor(status);
    // Only the "no device" state offers a CTA. Everything else is
    // a passive status indicator the parent doesn't need to act
    // on directly.
    final showPairCta = status == null;
    // Suppress the "Last seen" line for cases where it's not
    // meaningful (no device, or revoked). The label is enough.
    final showLastSeen = lastSeenAt != null &&
        (status == 'online' ||
            status == 'recent' ||
            status == 'stale');

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: showPairCta ? onPair : null,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 2,
                vertical: 2,
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: color == AppColors.disabled
                          ? AppColors.faint
                          : AppColors.ink2,
                      // Underline only on the no-device case so the
                      // tap target reads as actionable without
                      // adding visual noise to the active states.
                      decoration: showPairCta
                          ? TextDecoration.underline
                          : TextDecoration.none,
                    ),
                  ),
                  if (showPairCta) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      LucideIcons.chevronRight,
                      size: 12,
                      color: AppColors.faint,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (showLastSeen)
            Padding(
              padding: const EdgeInsets.only(top: 1, left: 11),
              child: Text(
                'Last seen ${_lastSeenLabel(lastSeenAt!)}',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.faint,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Mirrors the KidDevice.status labels. Kept inline here rather
  // than imported from KidDevice so this widget doesn't depend on
  // the model — easier to test and the strings stay co-located
  // with the colour mapping they drive.
  static (Color, String) _labelFor(String? status) => switch (status) {
        'online' => (AppColors.grass, 'Device online'),
        'recent' => (AppColors.warn, 'Device idle'),
        'stale' => (AppColors.muted, 'Device offline'),
        'revoked' => (AppColors.danger, 'Device revoked'),
        _ => (AppColors.disabled, 'No device paired'),
      };

  // Mirrors KidDevice.lastSeenLabel — copied so we don't drag the
  // full KidDevice model + its JSON-parsing surface into a test
  // for a UI caption. If the helpers ever diverge, that's a bug
  // — the dashboard caption and the device card should agree.
  static String _lastSeenLabel(DateTime lastSeen) {
    final now = DateTime.now();
    final delta = now.difference(lastSeen);
    if (delta.inSeconds < 30) return 'Just now';
    if (delta.inMinutes < 1) return '${delta.inSeconds}s ago';
    if (delta.inMinutes < 60) return '${delta.inMinutes} min ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    return '${delta.inDays}d ago';
  }
}
