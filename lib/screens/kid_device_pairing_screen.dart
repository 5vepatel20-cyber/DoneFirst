import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/child.dart';
import '../services/kid_device_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';

/// PIN-gated screen for managing kid-side device pairings. Shows:
///   • A "Pair new device" CTA per child in the family. Tapping
///     generates a 6-digit code via KidDeviceService and displays
///     it with a 10-minute countdown.
///   • A list of already-paired devices (across all children) with
///     online/offline status, last-seen-ago, and a Revoke button.
///
/// Accessed from Settings → "Devices" (PIN-gated via PinGuard).
class KidDevicePairingScreen extends StatefulWidget {
  /// Optional — when launched from the per-child popup menu, we
  /// preselect a child and skip the chooser.
  final String? preselectChildId;

  const KidDevicePairingScreen({super.key, this.preselectChildId});

  @override
  State<KidDevicePairingScreen> createState() => _KidDevicePairingScreenState();
}

class _KidDevicePairingScreenState extends State<KidDevicePairingScreen> {
  final _service = KidDeviceService();
  final _profile = ProfileService();

  bool _loading = true;
  String? _error;
  List<Child> _children = const [];
  List<KidDevice> _devices = const [];

  // Currently-active pairing code (only one shown at a time).
  GeneratedPairingCode? _activeCode;
  String? _activeCodeChildId;
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Pull the parent's children from the existing profile path
      // and the family's kid devices from the new view.
      final results = await Future.wait([
        _profile.children(),
        _service.listFamilyDevices(),
      ]);
      if (!mounted) return;
      setState(() {
        _children = results[0] as List<Child>;
        _devices = results[1] as List<KidDevice>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load: $e';
        _loading = false;
      });
    }
  }

  Future<void> _generateCode(String childId) async {
    setState(() => _error = null);
    try {
      final code = await _service.generatePairingCode(childId: childId);
      if (!mounted) return;
      _startCountdown(code);
      setState(() {
        _activeCode = code;
        _activeCodeChildId = childId;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Couldn’t generate a code: $e');
    }
  }

  void _startCountdown(GeneratedPairingCode code) {
    _countdownTimer?.cancel();
    _remaining = code.timeUntilExpiry;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining = code.expiresAt.difference(DateTime.now());
        if (_remaining.isNegative) {
          _countdownTimer?.cancel();
          _activeCode = null;
        }
      });
    });
  }

  Future<void> _revoke(KidDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke this device?'),
        content: Text(
          '“${device.deviceName ?? device.childDisplayName ?? 'Device'}” '
          'will be signed out immediately. The kid will need to '
          're-pair to use the app again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.revokeDevice(device.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn’t revoke: $e')),
      );
    }
  }

  String get _countdownLabel {
    final s = _remaining.inSeconds;
    if (s <= 0) return 'Expired';
    final m = s ~/ 60;
    final ss = s % 60;
    return '${m.toString().padLeft(1, '0')}:'
        '${ss.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: [
                      if (_activeCode != null) ...[
                        _ActiveCodeCard(
                          code: _activeCode!.code,
                          childName: _children
                              .firstWhere(
                                (c) => c.id == _activeCodeChildId,
                                orElse: () => Child(
                                  id: '',
                                  name: 'child',
                                ),
                              )
                              .name,
                          remaining: _countdownLabel,
                          onCopy: () {
                            Clipboard.setData(
                              ClipboardData(text: _activeCode!.code),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Code copied'),
                              ),
                            );
                          },
                          onCancel: () async {
                            try {
                              await _service
                                  .cancelPairingCode(_activeCode!.code);
                            } catch (_) {}
                            if (!mounted) return;
                            _countdownTimer?.cancel();
                            setState(() => _activeCode = null);
                          },
                        ),
                        const SizedBox(height: 24),
                      ],
                      Text(
                        'Pair a new device',
                        style: AppText.cardHeader(size: 15),
                      ),
                      const SizedBox(height: 8),
                      if (_children.isEmpty)
                        _EmptyState(
                          icon: LucideIcons.userPlus,
                          title: 'Add a child first',
                          subtitle: 'Pairing requires at least one child '
                              'in your family.',
                        )
                      else
                        ..._children.map(
                          (c) => _ChildPairRow(
                            child: c,
                            activeCodeChildId: _activeCodeChildId,
                            onGenerate: () => _generateCode(c.id),
                          ),
                        ),
                      const SizedBox(height: 32),
                      Text(
                        'Paired devices',
                        style: AppText.cardHeader(size: 15),
                      ),
                      const SizedBox(height: 8),
                      if (_devices.isEmpty)
                        _EmptyState(
                          icon: LucideIcons.smartphone,
                          title: 'No devices yet',
                          subtitle: 'Generate a code above and enter it '
                              'on the kid’s device.',
                        )
                      else
                        ..._devices.map((d) => _DeviceRow(
                              device: d,
                              onRevoke: () => _revoke(d),
                            )),
                    ],
                  ),
                ),
    );
  }
}

class _ActiveCodeCard extends StatelessWidget {
  const _ActiveCodeCard({
    required this.code,
    required this.childName,
    required this.remaining,
    required this.onCopy,
    required this.onCancel,
  });

  final String code;
  final String childName;
  final String remaining;
  final VoidCallback onCopy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.grassDeep,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.keyRound,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pair $childName’s device',
                  style: AppText.cardHeader(
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.timer,
                      size: 12,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      remaining,
                      style: AppText.body(
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: GestureDetector(
              onTap: onCopy,
              child: Text(
                code,
                style: AppText.code(size: 40),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Tap to copy • enter on the kid’s device',
              style: AppText.bodySecondary(
                color: Colors.white.withValues(alpha: 0.85),
                size: 12,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancel code'),
          ),
        ],
      ),
    );
  }
}

class _ChildPairRow extends StatelessWidget {
  const _ChildPairRow({
    required this.child,
    required this.activeCodeChildId,
    required this.onGenerate,
  });

  final Child child;
  final String? activeCodeChildId;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final isActive = activeCodeChildId == child.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isActive ? null : onGenerate,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.kidBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      child.name.isNotEmpty
                          ? child.name[0].toUpperCase()
                          : '?',
                      style: AppText.cardHeader(
                        color: AppColors.kidInk,
                        size: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        child.name,
                        style: AppText.cardHeader(size: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isActive
                            ? 'Code active — see above'
                            : 'Generate a 6-digit code',
                        style: AppText.bodySecondary(size: 12),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isActive ? LucideIcons.dot : LucideIcons.chevronRight,
                  color: isActive ? AppColors.grass : AppColors.muted,
                  size: isActive ? 18 : 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.onRevoke});

  final KidDevice device;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final (dotColor, statusLabel) = switch (device.status) {
      'online' => (AppColors.ok, 'Online'),
      'recent' => (AppColors.warn, 'Recent'),
      'stale' => (AppColors.muted, 'Stale'),
      'revoked' => (AppColors.danger, 'Revoked'),
      _ => (AppColors.muted, 'Never'),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.sageFill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  LucideIcons.smartphone,
                  size: 18,
                  color: AppColors.forest,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.deviceName ??
                          device.childDisplayName ??
                          'Device',
                      style: AppText.cardHeader(size: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${device.childDisplayName ?? '—'} • '
                      '${statusLabel} • '
                      '${device.lastSeenLabel(DateTime.now())}',
                      style: AppText.bodySecondary(size: 12),
                    ),
                  ],
                ),
              ),
              if (!device.isRevoked)
                IconButton(
                  tooltip: 'Revoke',
                  icon: const Icon(LucideIcons.trash2, size: 16),
                  color: AppColors.danger,
                  onPressed: onRevoke,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hair2),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.muted, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.cardHeader(size: 14)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppText.bodySecondary(size: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.alertCircle,
              size: 32,
              color: AppColors.danger,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: AppText.body(size: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
