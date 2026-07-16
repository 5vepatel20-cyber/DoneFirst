import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/blocking_service.dart';
import '../theme/app_theme.dart';

/// First-run setup screen for the two Android permissions the
/// parent app needs before it can enforce a homework lock:
///
///   • **Usage access** — lets the underlying `flutter_screentime`
///     plugin see which app is foregrounded, so it can decide when
///     to invoke the block screen.
///
///   • **Display over other apps** — lets the block screen render
///     on top of any app the kid tries to open during a lock.
///
/// Both come from the `donefirst/permissions` MethodChannel
/// (see `MainActivity.kt`), so the rows reflect the real OS-level
/// state — including the case where the user flipped only one
/// toggle in Settings and came back. The primary Continue button
/// stays disabled until every required permission is granted.
///
/// Reachable from:
///   • `lock_config_screen` when the user tries to start a lock
///     without the OS-level grants in place
///   • Settings → "Device permissions" (manual re-check)
///
/// On iOS / web / Flutter test the channel returns "granted" for
/// both rows via `MissingPluginException`, so the screen's
/// Continue button is always enabled and the user is never trapped
/// on a screen that asks for a permission the platform doesn't
/// expose.
class DevicePermissionsScreen extends StatefulWidget {
  /// Optional continuation handler. Called when the user taps
  /// Continue after granting every permission. The caller
  /// typically starts the original lock flow that routed them
  /// here in the first place.
  final VoidCallback? onContinue;

  const DevicePermissionsScreen({super.key, this.onContinue});

  @override
  State<DevicePermissionsScreen> createState() =>
      _DevicePermissionsScreenState();
}

class _DevicePermissionsScreenState extends State<DevicePermissionsScreen>
    with WidgetsBindingObserver {
  final _blocking = BlockingService();
  final Map<BlockingPermission, bool> _granted = {
    for (final p in BlockingPermission.values) p: false,
  };
  bool _loading = true;
  // Per-row "opening Settings…" indicator so the disabled state
  // doesn't blanket the whole button while a single permission is
  // being requested.
  final Set<BlockingPermission> _pending = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user just came back from the OS settings screen where
    // they flipped a toggle. Re-check both permissions so the
    // affected row flips from "Grant" to "✓ On" without them
    // having to tap anything on this screen.
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final next = await _blocking.currentPermissions();
    if (!mounted) return;
    setState(() {
      _granted
        ..clear()
        ..addAll(next);
      _loading = false;
    });
  }

  Future<void> _grant(BlockingPermission permission) async {
    if (_pending.contains(permission)) return;
    setState(() => _pending.add(permission));
    try {
      await _blocking.openPermissionSettings(permission);
    } finally {
      if (mounted) setState(() => _pending.remove(permission));
    }
  }

  bool get _allGranted =>
      _granted.values.every((g) => g) && !_loading;

  void _continue() {
    if (!_allGranted) return;
    if (widget.onContinue != null) {
      widget.onContinue!();
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text('Quick setup'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            12,
            AppSpacing.screenPadding,
            AppSpacing.screenPadding,
          ),
          children: [
            Text(
              'Two permissions for homework locks',
              style: AppText.screenTitle(),
            ),
            const SizedBox(height: 6),
            Text(
              'DoneFirst needs a couple of Android settings so it can '
              'keep the kid in the lock screen during a homework session.',
              style: AppText.bodySecondary(size: 13.5),
            ),
            const SizedBox(height: AppSpacing.blockGap),
            const _PrivacyBanner(),
            const SizedBox(height: AppSpacing.blockGap),
            _PermissionRow(
              permission: BlockingPermission.usageAccess,
              icon: LucideIcons.activity,
              title: 'Usage access',
              description:
                  'Lets DoneFirst see which apps are open so it can '
                  'block the right ones during a lock.',
              granted: _granted[BlockingPermission.usageAccess] ?? false,
              pending: _pending.contains(BlockingPermission.usageAccess),
              loading: _loading,
              onGrant: () => _grant(BlockingPermission.usageAccess),
            ),
            const SizedBox(height: 10),
            _PermissionRow(
              permission: BlockingPermission.overlay,
              icon: LucideIcons.appWindow,
              title: 'Display over other apps',
              description:
                  'Lets the lock screen show on top of any app the '
                  'kid tries to open during a homework session.',
              granted: _granted[BlockingPermission.overlay] ?? false,
              pending: _pending.contains(BlockingPermission.overlay),
              loading: _loading,
              onGrant: () => _grant(BlockingPermission.overlay),
            ),
            const SizedBox(height: AppSpacing.blockGap),
            _ContinueButton(
              enabled: _allGranted,
              onPressed: _continue,
            ),
            const SizedBox(height: 10),
            if (!_allGranted && !_loading)
              Center(
                child: Text(
                  'Tap “Grant” above, then flip the toggle in Settings.',
                  style: AppText.bodySecondary(size: 12),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// `sageFill`-tinted privacy banner shown at the top of the
/// screen. Reused visually in the parent-app design language —
/// the copy is specific to device permissions so it's inline.
class _PrivacyBanner extends StatelessWidget {
  const _PrivacyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.sageFill,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hair2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            LucideIcons.shieldCheck,
            size: 18,
            color: AppColors.forest,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Neither permission is shared with us or anyone else. '
              'Usage access stays on this device, and “display over '
              'other apps” only ever draws the DoneFirst lock screen.',
              style: AppText.body(size: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row per Android permission. The status pill on the right
/// flips between a "Grant" action and a green "✓ On" indicator
/// depending on the OS-level grant state.
class _PermissionRow extends StatelessWidget {
  final BlockingPermission permission;
  final IconData icon;
  final String title;
  final String description;
  final bool granted;
  final bool pending;
  final bool loading;
  final VoidCallback onGrant;

  const _PermissionRow({
    required this.permission,
    required this.icon,
    required this.title,
    required this.description,
    required this.granted,
    required this.pending,
    required this.loading,
    required this.onGrant,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hair2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: granted ? AppColors.okFill : AppColors.sageFill,
              borderRadius: BorderRadius.circular(AppRadius.iconTile),
            ),
            child: Icon(
              icon,
              size: 20,
              color: granted ? AppColors.ok : AppColors.forest,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.cardHeader(size: 14.5)),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: AppText.bodySecondary(size: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _StatusPill(
            granted: granted,
            pending: pending,
            loading: loading,
            onGrant: onGrant,
          ),
        ],
      ),
    );
  }
}

/// Right-hand pill on a permission row. Three visual states:
///   • loading shimmer (compact spinner)
///   • granted → filled green "✓ On"
///   • denied  → outlined "Grant" CTA
class _StatusPill extends StatelessWidget {
  final bool granted;
  final bool pending;
  final bool loading;
  final VoidCallback onGrant;

  const _StatusPill({
    required this.granted,
    required this.pending,
    required this.loading,
    required this.onGrant,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        width: 56,
        height: 28,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.muted,
            ),
          ),
        ),
      );
    }
    if (granted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.okFill,
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: Border.all(color: AppColors.ok),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.check,
              size: 12,
              color: AppColors.ok,
            ),
            const SizedBox(width: 4),
            Text(
              'On',
              style: AppText.cardHeader(size: 12, color: AppColors.ok),
            ),
          ],
        ),
      );
    }
    return OutlinedButton(
      onPressed: pending ? null : onGrant,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.forest,
        side: const BorderSide(color: AppColors.forest),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: const Size(72, 32),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
      child: pending
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.forest,
              ),
            )
          : const Text(
              'Grant',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

/// Full-width primary CTA at the bottom. Disabled until every
/// required permission is granted; the helper line under the
/// button tells the user what to do next when disabled.
class _ContinueButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const _ContinueButton({required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.forest,
        disabledBackgroundColor: AppColors.disabled,
        disabledForegroundColor: AppColors.disabledText,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
      child: const Text(
        'Continue',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }
}
