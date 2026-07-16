import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../models/child.dart';
import '../services/kid_device_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/destructive_confirm_dialog.dart';
import '../app_globals.dart' as app;
import 'kid_device_setup_screen.dart';

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
  final _eventService = KidDeviceEventService();
  final _sessionService = SessionService();

  bool _loading = true;
  String? _error;
  List<Child> _children = const [];
  List<KidDevice> _devices = const [];
  List<KidDeviceEvent> _events = const [];

  // Currently-active pairing code (only one shown at a time).
  GeneratedPairingCode? _activeCode;
  String? _activeCodeChildId;
  Timer? _countdownTimer;
  // Flip to true when the active code's countdown reaches zero,
  // and stays true until the parent either generates a new code
  // or navigates away. Drives the inline "Code expired" CTA so
  // the parent doesn't have to scroll back to the per-child
  // "Pair new device" button to recover.
  bool _codeExpired = false;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _load();
    // Realtime hookup. The RealtimeService is a process-wide
    // singleton started by ParentDashboard.initState, so we just
    // register a callback; we DON'T start/stop listening here.
    _previousOnNewEvent = app.realtimeService.onNewKidDeviceEvent;
    app.realtimeService.onNewKidDeviceEvent = _onRealtimeEvent;
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    // Restore the previous callback instead of nulling it outright,
    // so disposing this screen while another screen (the dashboard)
    // is also subscribed doesn't blow away their subscription.
    app.realtimeService.onNewKidDeviceEvent = _previousOnNewEvent;
    super.dispose();
  }

  /// Cached pointer to whatever callback was registered before
  /// this screen registered itself. Restored in [dispose] so we
  /// chain handlers instead of clobbering.
  void Function(Map<String, dynamic>)? _previousOnNewEvent;

  void _onRealtimeEvent(Map<String, dynamic> newRow) {
    // RLS keeps realtime scoped to the parent's family, but the
    // event row only contains the raw columns (no child_name /
    // device_name join). Cheapest correct path: refetch the
    // joined view. The list is bounded to 25 events, so this is
    // a single small query — fine to do per realtime tick.
    final familyId = newRow['family_id'];
    if (familyId == null) return;

    // Hot-path: if a code_claimed event landed for the active code
    // we're displaying, clear it immediately so the parent sees
    // the loop close ("code entered → kid device appears in list")
    // instead of watching the timer tick down a code the kid has
    // already used.
    final eventType = newRow['event_type'] as String?;
    final claimedCode = newRow['device_pairing_code'] as String?;
    if (eventType == KidDeviceEvent.typeCodeClaimed &&
        claimedCode != null &&
        _activeCode != null &&
        claimedCode == _activeCode!.code) {
      _countdownTimer?.cancel();
      setState(() {
        _activeCode = null;
        _activeCodeChildId = null;
      });
      // Refresh devices so the newly-paired one shows in the list
      // immediately, not 10s later when the next poll runs.
      _refreshDevices();
      // The activity feed below will pick up the claim event via
      // the regular refetch path below; no need to fetch it here.
    }

    _eventService.listFamilyEvents().then((updated) {
      if (!mounted) return;
      // Skip the refetch if the IDs we already have are still
      // current; this avoids a redundant setState during the
      // initial open when realtime floods multiple inserts at once.
      if (updated.length == _events.length &&
          updated.isNotEmpty &&
          updated.first.id == _events.first.id) {
        return;
      }
      setState(() => _events = updated);
    }).catchError((_) {
      // Realtime refetch failures are non-fatal — the 10s
      // pull-to-refresh path will heal the feed on the next
      // user gesture. Swallow to avoid spamming snackbars.
    });
  }

  /// Lighter refetch that only updates the device list (no event
  /// fetch). Called when we know a claim just succeeded and want
  /// to show the new device as fast as possible.
  Future<void> _refreshDevices() async {
    try {
      final devices = await _service.listFamilyDevices();
      if (!mounted) return;
      setState(() => _devices = devices);
    } catch (_) {
      // Non-fatal — pull-to-refresh will heal it.
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Pull the parent's children from the existing session path
      // and the family's kid devices + audit events from the new
      // views. All independent — fire in parallel.
      final results = await Future.wait([
        _sessionService.getChildren(),
        _service.listFamilyDevices(),
        _eventService.listFamilyEvents(),
      ]);
      if (!mounted) return;
      setState(() {
        _children = results[0] as List<Child>;
        _devices = results[1] as List<KidDevice>;
        _events = results[2] as List<KidDeviceEvent>;
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
    _codeExpired = false;
    _remaining = code.timeUntilExpiry;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining = code.expiresAt.difference(DateTime.now());
        if (_remaining.isNegative) {
          _countdownTimer?.cancel();
          _activeCode = null;
          // Keep _activeCodeChildId so the expired-state card can
          // re-show the right "Generate a new code for [child]"
          // CTA. Cleared on next generate or on dismiss.
          _codeExpired = true;
        }
      });
    });
  }

  Future<void> _revoke(KidDevice device) async {
    final name =
        device.deviceName ?? device.childDisplayName ?? 'Device';
    final confirmed = await DestructiveConfirmDialog.show(
      context,
      title: 'Revoke $name?',
      description:
          '“$name” will be signed out immediately on the kid’s phone. '
          'To use the app again, the kid will need to enter a new '
          'pairing code generated from this device.',
      confirmPhrase: name,
      confirmButtonLabel: 'Revoke',
      warningText:
          'Any in-progress homework session on this device will end '
          'without the usual completion celebration.',
    );
    if (!confirmed) return;
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

  Future<void> _showRenameDialog(KidDevice device) async {
    final controller = TextEditingController(text: device.deviceName ?? '');
    try {
      final newName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rename device'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Device name',
              hintText: 'e.g. Bedroom tablet, School iPad',
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (newName == null) return;
      // Empty string clears the override and falls back to the
      // kid-side default. Don't pass through unchanged text —
      // that's a no-op DB call we can avoid.
      if (newName.trim() == (device.deviceName ?? '').trim()) return;
      try {
        await _service.renameDevice(device.id, newName);
        await _load();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Couldn’t rename: $e')),
        );
      }
    } finally {
      // Single dispose site covers cancel, no-op, success, server
      // error, AND the early `if (!mounted) return;` inside the
      // catch block. The previous three separate dispose calls
      // missed the unmounted-during-error path — every rename in
      // that race would leak one controller + its listeners.
      controller.dispose();
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

  Future<void> _shareCode({
    required GeneratedPairingCode code,
    required String childName,
  }) async {
    // Compose a kid-friendly share text. We don't include the code
    // itself in a way that screams "OTP" because (a) WhatsApp/SMS
    // previews often truncate the body and (b) parents sometimes
    // hand the kid their phone to enter the code anyway, so it's
    // not really a secret from the kid — only from the world.
    // The expiration copy uses the original `validFor` duration
    // (not the time-remaining) so the recipient isn't lied to if
    // they open the message a few minutes after it's sent.
    final minutes = code.validFor.inMinutes;
    final expiresIn = minutes == 1 ? '1 minute' : '$minutes minutes';
    final text =
        'DoneFirst pairing code for $childName’s device: ${code.code} '
        '(expires in $expiresIn). '
        'Open DoneFirst on the kid’s phone, choose “Kid”, and '
        'enter the code.';
    try {
      await SharePlus.instance.share(
        ShareParams(text: text, subject: 'DoneFirst pairing code'),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn’t share: $e')),
      );
    }
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
                          onShare: () => _shareCode(
                            code: _activeCode!,
                            childName: _children
                                .firstWhere(
                                  (c) => c.id == _activeCodeChildId,
                                  orElse: () => Child(
                                    id: '',
                                    name: 'your child',
                                  ),
                                )
                                .name,
                          ),
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
                      ] else if (_codeExpired && _activeCodeChildId != null) ...[
                        _ExpiredCodeCard(
                          childName: _children
                              .firstWhere(
                                (c) => c.id == _activeCodeChildId,
                                orElse: () => Child(
                                  id: '',
                                  name: 'child',
                                ),
                              )
                              .name,
                          onGenerate: () {
                            setState(() => _codeExpired = false);
                            _generateCode(_activeCodeChildId!);
                          },
                          onDismiss: () {
                            setState(() {
                              _codeExpired = false;
                              _activeCodeChildId = null;
                            });
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
                              onRename: () => _showRenameDialog(d),
                            )),
                      const SizedBox(height: 32),
                      _SetupGuideRow(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const KidDeviceSetupScreen(),
                          ),
                        ),
                      ),
                      if (_devices.isEmpty && _events.isEmpty) const SizedBox(height: 32),
                      Text(
                        'Recent activity',
                        style: AppText.cardHeader(size: 15),
                      ),
                      const SizedBox(height: 8),
                      if (_events.isEmpty)
                        _EmptyState(
                          icon: LucideIcons.history,
                          title: 'No activity yet',
                          subtitle: 'Pairings, claims, and revokes show '
                              'up here once you start using kid devices.',
                        )
                      else
                        ..._events
                            .take(8)
                            .map((e) => _ActivityRow(event: e)),
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
    required this.onShare,
    required this.onCancel,
  });

  final String code;
  final String childName;
  final String remaining;
  final VoidCallback onCopy;
  final VoidCallback onShare;
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: onShare,
                icon: const Icon(LucideIcons.share2, size: 16),
                label: const Text('Share'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                ),
              ),
              TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                ),
                child: const Text('Cancel code'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact card shown in place of the active-code card when the
/// countdown reaches zero. Without this, the parent has to scroll
/// back to the per-child "Pair new device" row to recover — easy
/// to miss on a long list of devices.
class _ExpiredCodeCard extends StatelessWidget {
  final String childName;
  final VoidCallback onGenerate;
  final VoidCallback onDismiss;

  const _ExpiredCodeCard({
    required this.childName,
    required this.onGenerate,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warnFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warnBd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.clock, size: 18, color: AppColors.warn),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Code for $childName expired',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Generate a new code to keep pairing.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: onGenerate,
                      icon: const Icon(LucideIcons.refreshCw, size: 14),
                      label: const Text('Generate new code'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: onDismiss,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ],
            ),
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
  const _DeviceRow({
    required this.device,
    required this.onRevoke,
    required this.onRename,
  });

  final KidDevice device;
  final VoidCallback onRevoke;
  final VoidCallback onRename;

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
                      '$statusLabel • '
                      '${device.lastSeenLabel(DateTime.now())}',
                      style: AppText.bodySecondary(size: 12),
                    ),
                  ],
                ),
              ),
              if (!device.isRevoked) ...[
                IconButton(
                  tooltip: 'Rename',
                  icon: const Icon(LucideIcons.pencil, size: 16),
                  color: AppColors.ink2,
                  onPressed: onRename,
                ),
                IconButton(
                  tooltip: 'Revoke',
                  icon: const Icon(LucideIcons.trash2, size: 16),
                  color: AppColors.danger,
                  onPressed: onRevoke,
                ),
              ],
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

/// Tappable row that opens the setup guide. Sits between the
/// paired-devices list and the activity feed — parents who finish
/// reading the empty state typically wonder "what's next?" and
/// this is the answer.
class _SetupGuideRow extends StatelessWidget {
  const _SetupGuideRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.sageFill,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    LucideIcons.helpCircle,
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
                        'How to set up the kid’s device',
                        style: AppText.cardHeader(size: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Install the app, grant access, run one ADB '
                        'command — full walk-through with copy-able '
                        'steps.',
                        style: AppText.bodySecondary(size: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  LucideIcons.chevronRight,
                  color: AppColors.muted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Single line in the recent-activity feed. The event_type drives
/// the icon + color so the parent can scan the feed at a glance.
/// Time-ago label right-aligned via Expanded above.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.event});

  final KidDeviceEvent event;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (event.eventType) {
      KidDeviceEvent.typeCodeGenerated => (LucideIcons.keyRound, AppColors.forest),
      KidDeviceEvent.typeCodeClaimed => (LucideIcons.link, AppColors.grass),
      KidDeviceEvent.typeCodeCancelled => (LucideIcons.x, AppColors.muted),
      KidDeviceEvent.typeDeviceRevoked => (LucideIcons.trash2, AppColors.danger),
      _ => (LucideIcons.circle, AppColors.muted),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.hair2),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                event.label(),
                style: AppText.body(size: 13),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              event.ageLabel(DateTime.now()),
              style: AppText.bodySecondary(size: 12),
            ),
          ],
        ),
      ),
    );
  }
}
