import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/blocking_service.dart';
import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';

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

  bool get _allGranted => _granted.values.every((g) => g) && !_loading;

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
      appBar: AppBar(title: const Text('Quick setup')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            12,
            AppSpacing.screenPadding,
            AppSpacing.screenPadding,
          ),
          children: [
            Text('Two permissions for locks', style: AppText.screenTitle()),
            const SizedBox(height: 6),
            Text(
              'So DoneFirst can keep the kid in the lock screen during '
              'a session.',
              style: AppText.bodySecondary(size: 13.5),
            ),
            const SizedBox(height: AppSpacing.blockGap),
            const _PrivacyBanner(),
            const SizedBox(height: AppSpacing.blockGap),
            _PermissionRow(
              permission: BlockingPermission.usageAccess,
              icon: LucideIcons.activity,
              title: 'Usage access',
              description: 'Lets DoneFirst see which apps are open.',
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
              description: 'Lets the lock screen show on top of any app.',
              granted: _granted[BlockingPermission.overlay] ?? false,
              pending: _pending.contains(BlockingPermission.overlay),
              loading: _loading,
              onGrant: () => _grant(BlockingPermission.overlay),
            ),
            const SizedBox(height: AppSpacing.blockGap),
            DfButton('Continue', onPressed: _allGranted ? _continue : null),
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

/// `greenTint`-tinted reassurance banner shown at the top of the
/// screen. Copy is specific to device permissions so it's inline.
class _PrivacyBanner extends StatelessWidget {
  const _PrivacyBanner();

  @override
  Widget build(BuildContext context) {
    return DfCard(
      color: AppColors.greenTint,
      borderColor: AppColors.greenTint,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.shieldCheck, size: 18, color: AppColors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Neither permission is shared with us. Both stay on this '
              'device.',
              style: AppText.body(size: 13, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row per Android permission. The control on the right flips
/// between a "Grant" action and a green "On" status pill depending
/// on the OS-level grant state.
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
    return DfCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.greenTint,
              borderRadius: BorderRadius.circular(AppRadius.iconTile),
            ),
            child: Icon(icon, size: 20, color: AppColors.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.cardHeader(size: 15)),
                const SizedBox(height: 4),
                Text(description, style: AppText.bodySecondary(size: 12.5)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _StatusControl(
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

/// Right-hand control on a permission row. Three visual states:
///   • loading   → compact spinner
///   • granted   → green "On" status pill
///   • otherwise → outlined "Grant" CTA
class _StatusControl extends StatelessWidget {
  final bool granted;
  final bool pending;
  final bool loading;
  final VoidCallback onGrant;

  const _StatusControl({
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
        height: 32,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.ink45,
            ),
          ),
        ),
      );
    }
    if (granted) {
      return const DfStatusPill(
        'On',
        tone: DfPillTone.success,
        icon: LucideIcons.check,
      );
    }
    return GestureDetector(
      onTap: pending ? null : onGrant,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: Border.all(color: AppColors.green, width: 1.5),
        ),
        child: pending
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.green,
                ),
              )
            : Text(
                'Grant',
                style: AppText.button(color: AppColors.green, size: 14),
              ),
      ),
    );
  }
}
