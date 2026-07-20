import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_theme.dart';

/// A discreet settings affordance for the kid app.
///
/// Once a device is paired, every kid screen (home, locked, break,
/// waiting) is otherwise a dead end — there is no way to unpair the
/// device, switch to a sibling, or back out of a bad pairing. That
/// stranded a parent who wanted to hand the tablet to another child
/// or reset it. This gear opens a sheet showing who the device is
/// paired to and an "Unpair this device" action (confirmed first, so
/// a curious kid can't casually escape blocking).
class KidSettingsButton extends StatelessWidget {
  /// Name of the child this device is currently paired to.
  final String childName;

  /// Clears the session and returns to the pairing screen. Wired to
  /// [kid_root]'s unpair handler, which also stops realtime/heartbeat.
  final Future<void> Function() onUnpair;

  /// Icon tint. Defaults to a muted grey that recedes on the home
  /// screen; the waiting screen passes a warmer tone to sit on its
  /// warn-coloured background.
  final Color color;

  const KidSettingsButton({
    super.key,
    required this.childName,
    required this.onUnpair,
    this.color = AppColors.muted,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(LucideIcons.settings, size: 22, color: color),
      tooltip: 'Device settings',
      onPressed: () => _openSheet(context),
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.kidCard),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.kidLine,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Device settings',
                  style: AppText.cardHeader(size: 18, color: AppColors.kidInk),
                ),
                const SizedBox(height: 4),
                Text(
                  'Paired to $childName',
                  style: AppText.bodySecondary(size: 13),
                ),
                const SizedBox(height: 20),
                _ActionRow(
                  icon: LucideIcons.unlink,
                  tint: AppColors.danger,
                  fill: AppColors.dangerFill,
                  title: 'Unpair this device',
                  body:
                      'Sign out and go back to the pairing screen. '
                      'App blocking stops until this device is paired '
                      'again — a parent will need the pairing code.',
                  onTap: () => _confirmUnpair(sheetContext),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: Text(
                      'Cancel',
                      style: AppText.body(size: 14, color: AppColors.muted),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmUnpair(BuildContext sheetContext) async {
    // Capture the navigator before the async gap so we don't touch a
    // BuildContext across await.
    final sheetNavigator = Navigator.of(sheetContext);
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          'Unpair this device?',
          style: AppText.cardHeader(size: 18, color: AppColors.kidInk),
        ),
        content: Text(
          "$childName's device will stop being managed until it's "
          'paired again with a new code. You can re-pair any time.',
          style: AppText.bodySecondary(size: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Keep paired',
              style: AppText.body(size: 14, color: AppColors.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Unpair',
              style: AppText.body(size: 14, color: AppColors.danger),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    // Close the settings sheet first, then run the unpair. Routing
    // back to the pairing screen is driven by KidAuthService's
    // notifyListeners() rebuilding kid_root.
    sheetNavigator.pop();
    await onUnpair();
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final Color fill;
  final String title;
  final String body;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.tint,
    required this.fill,
    required this.title,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.kidCard),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.kidBg,
            borderRadius: BorderRadius.circular(AppRadius.kidCard),
            border: Border.all(color: AppColors.kidLine),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(AppRadius.iconTile),
                ),
                child: Icon(icon, size: 20, color: tint),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.cardHeader(
                        size: 15,
                        color: AppColors.kidInk,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(body, style: AppText.bodySecondary(size: 12.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
