import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../models/child.dart';
import '../services/kid_device_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';
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
    final eventType = newRow['event_type'] as String?;
    final claimedCode = newRow['device_pairing_code'] as String?;
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

    _eventService
        .listFamilyEvents()
        .then((updated) {
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
        })
        .catchError((_) {
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
      // Defensive: if the initial time-until-expiry is already
      // non-positive (timezone/storage race we don't fully trust),
      // skip rendering an Active card that just says "Expired".
      // Jump straight to the Expired state so the parent can
      // retry instead of seeing the card flash and vanish.
      final alreadyExpired =
          !code.timeUntilExpiry.isNegative &&
          code.timeUntilExpiry == Duration.zero;
      setState(() {
        _activeCode = alreadyExpired ? null : code;
        _activeCodeChildId = childId;
        _codeExpired = alreadyExpired;
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
    final name = device.deviceName ?? device.childDisplayName ?? 'Device';
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Couldn’t revoke: $e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Couldn’t rename: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Couldn’t share: $e')));
    }
  }

  String _childName(String? id, {String fallback = 'child'}) {
    return _children
        .firstWhere(
          (c) => c.id == id,
          orElse: () => Child(id: '', name: fallback),
        )
        .name;
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
          ? const _LoadingView()
          : _error != null
          ? _ErrorView(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  12,
                  AppSpacing.screenPadding,
                  32,
                ),
                children: [
                  if (_activeCode != null) ...[
                    _ActiveCodeCard(
                      code: _activeCode!.code,
                      childName: _childName(_activeCodeChildId),
                      remaining: _countdownLabel,
                      onCopy: () {
                        Clipboard.setData(
                          ClipboardData(text: _activeCode!.code),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Code copied')),
                        );
                      },
                      onShare: () => _shareCode(
                        code: _activeCode!,
                        childName: _childName(
                          _activeCodeChildId,
                          fallback: 'your child',
                        ),
                      ),
                      onCancel: () async {
                        try {
                          await _service.cancelPairingCode(_activeCode!.code);
                        } catch (_) {}
                        if (!mounted) return;
                        _countdownTimer?.cancel();
                        setState(() => _activeCode = null);
                      },
                    ),
                    const SizedBox(height: 24),
                  ] else if (_codeExpired && _activeCodeChildId != null) ...[
                    _ExpiredCodeCard(
                      childName: _childName(_activeCodeChildId),
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
                  DfSectionLabel(
                    _activeCode != null
                        ? 'Or pick another kid'
                        : 'Pair a device',
                  ),
                  if (_children.isEmpty)
                    const DfEmptyState(
                      icon: LucideIcons.userPlus,
                      title: 'Add a kid first',
                      hint:
                          'Pairing needs at least one kid in your '
                          'family.',
                    )
                  else
                    ..._children.map(
                      (c) => _ChildPairRow(
                        child: c,
                        activeCodeChildId: _activeCodeChildId,
                        onGenerate: () => _generateCode(c.id),
                      ),
                    ),
                  const SizedBox(height: 28),
                  DfSectionLabel('Paired · ${_devices.length}'),
                  if (_devices.isEmpty)
                    const DfEmptyState(
                      icon: LucideIcons.smartphone,
                      title: 'No devices yet',
                      hint:
                          'Generate a code above and enter it on '
                          'the kid’s device.',
                    )
                  else
                    ..._devices.map(
                      (d) => _DeviceRow(
                        device: d,
                        onRevoke: () => _revoke(d),
                        onRename: () => _showRenameDialog(d),
                      ),
                    ),
                  const SizedBox(height: 20),
                  _SetupGuideRow(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const KidDeviceSetupScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  DfSectionLabel('Recent activity'),
                  if (_events.isEmpty)
                    const DfEmptyState(
                      icon: LucideIcons.history,
                      title: 'No activity yet',
                      hint:
                          'Pairings, claims, and revokes show up '
                          'here once you start using kid devices.',
                    )
                  else
                    ..._events.take(8).map((e) => _ActivityRow(event: e)),
                ],
              ),
            ),
    );
  }
}

/// Small square icon tile used across this screen's rows.
class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.icon,
    this.bg = AppColors.greenTint,
    this.fg = AppColors.green,
    this.size = 44,
  });

  final IconData icon;
  final Color bg;
  final Color fg;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.iconTile),
      ),
      child: Icon(icon, size: size * 0.42, color: fg),
    );
  }
}

/// The green pairing-code hero card. Big spaced digits, a live
/// countdown pill, tap-to-copy, and Share / Cancel actions.
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
    final spaced = code.split('').join('  ');
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.green,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: const Icon(
                  LucideIcons.keyRound,
                  color: Colors.white,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pair $childName’s device',
                  style: AppText.cardHeader(size: 16, color: Colors.white),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.timer,
                      size: 13,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      remaining,
                      style: AppText.timerDigits(size: 13, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Center(
            child: GestureDetector(
              onTap: onCopy,
              behavior: HitTestBehavior.opaque,
              child: Text(
                spaced,
                style: AppText.code(size: 34, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              'Tap to copy · enter on the kid’s device',
              style: AppText.bodySecondary(
                color: Colors.white.withValues(alpha: 0.85),
                size: 12.5,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _CodeAction(
                  icon: LucideIcons.share2,
                  label: 'Share',
                  onTap: onShare,
                  filled: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CodeAction(
                  icon: LucideIcons.x,
                  label: 'Cancel code',
                  onTap: onCancel,
                  filled: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Share / Cancel pill used on the green code card. [filled] gives a
/// white button with green label; otherwise a translucent outline.
class _CodeAction extends StatelessWidget {
  const _CodeAction({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.filled,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? AppColors.greenDeep : Colors.white;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? Colors.white : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: filled
              ? null
              : Border.all(
                  color: Colors.white.withValues(alpha: 0.45),
                  width: 1.4,
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 7),
            Text(label, style: AppText.button(color: fg, size: 14)),
          ],
        ),
      ),
    );
  }
}

/// Amber recovery card shown when the active code's countdown hits
/// zero, so the parent can re-generate without hunting for the row.
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
    return DfCard(
      color: AppColors.amberTint,
      borderColor: AppColors.amberTint2,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.clock, size: 18, color: AppColors.amberDeep),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Code for $childName expired',
                  style: AppText.cardHeader(size: 15),
                ),
                const SizedBox(height: 3),
                Text(
                  'Generate a new code to keep pairing.',
                  style: AppText.bodySecondary(size: 12.5),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    DfButton.amber(
                      'New code',
                      icon: LucideIcons.refreshCw,
                      onPressed: onGenerate,
                      expand: false,
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: onDismiss,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 14,
                        ),
                        child: Text(
                          'Dismiss',
                          style: AppText.button(
                            color: AppColors.ink70,
                            size: 14,
                          ),
                        ),
                      ),
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

/// Per-child "generate a code" row.
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
      padding: const EdgeInsets.only(bottom: 10),
      child: DfCard(
        padding: const EdgeInsets.all(14),
        onTap: isActive ? null : onGenerate,
        child: Row(
          children: [
            DfAvatar(child.name, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(child.name, style: AppText.cardHeader(size: 15)),
                  const SizedBox(height: 2),
                  Text(
                    isActive
                        ? 'Code active — see above'
                        : 'Generate a 6-digit code',
                    style: AppText.bodySecondary(size: 12.5),
                  ),
                ],
              ),
            ),
            if (isActive)
              const DfStatusPill('Active', tone: DfPillTone.success, dot: true)
            else
              const Icon(
                LucideIcons.chevronRight,
                color: AppColors.ink45,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

/// One paired-device row with a status pill, last-seen, rename and
/// revoke actions.
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
    final (tone, statusLabel) = switch (device.status) {
      'online' => (DfPillTone.success, 'Online'),
      'recent' => (DfPillTone.attention, 'Recent'),
      'stale' => (DfPillTone.neutral, 'Stale'),
      'revoked' => (DfPillTone.danger, 'Revoked'),
      _ => (DfPillTone.neutral, 'Never'),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DfCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const _IconTile(icon: LucideIcons.smartphone),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.deviceName ?? device.childDisplayName ?? 'Device',
                    style: AppText.cardHeader(size: 15),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      DfStatusPill(statusLabel, tone: tone, dot: true),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '${device.childDisplayName ?? '—'} · '
                          '${device.lastSeenLabel(DateTime.now())}',
                          style: AppText.bodySecondary(size: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!device.isRevoked) ...[
              IconButton(
                tooltip: 'Rename',
                icon: const Icon(LucideIcons.pencil, size: 16),
                color: AppColors.ink70,
                onPressed: onRename,
              ),
              IconButton(
                tooltip: 'Revoke',
                icon: const Icon(LucideIcons.trash2, size: 16),
                color: AppColors.dangerFg,
                onPressed: onRevoke,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Full-screen error state with a retry.
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
            const _IconTile(
              icon: LucideIcons.alertCircle,
              bg: AppColors.dangerBg,
              fg: AppColors.dangerFg,
              size: 60,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: AppText.body(size: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            DfButton.outline(
              'Try again',
              icon: LucideIcons.refreshCw,
              onPressed: onRetry,
              expand: false,
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton placeholder shown while the first load is in flight.
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        12,
        AppSpacing.screenPadding,
        32,
      ),
      children: const [
        _SkeletonBox(height: 200),
        SizedBox(height: 24),
        _SkeletonBox(height: 14, width: 120),
        SizedBox(height: 14),
        _SkeletonBox(height: 72),
        SizedBox(height: 10),
        _SkeletonBox(height: 72),
        SizedBox(height: 28),
        _SkeletonBox(height: 14, width: 100),
        SizedBox(height: 14),
        _SkeletonBox(height: 72),
      ],
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.height, this.width});

  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: AppColors.border2,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    );
  }
}

/// Tappable row that opens the setup guide.
class _SetupGuideRow extends StatelessWidget {
  const _SetupGuideRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DfCard(
      color: AppColors.greenTint,
      borderColor: AppColors.greenTint,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          const _IconTile(icon: LucideIcons.helpCircle, bg: AppColors.card),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How to set up the kid’s device',
                  style: AppText.cardHeader(size: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  'Install the app, grant access, run one ADB command — '
                  'a full walk-through with copy-able steps.',
                  style: AppText.bodySecondary(size: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            LucideIcons.chevronRight,
            color: AppColors.ink45,
            size: 20,
          ),
        ],
      ),
    );
  }
}

/// Single line in the recent-activity feed.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.event});

  final KidDeviceEvent event;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (event.eventType) {
      KidDeviceEvent.typeCodeGenerated => (
        LucideIcons.keyRound,
        AppColors.green,
      ),
      KidDeviceEvent.typeCodeClaimed => (LucideIcons.link, AppColors.green),
      KidDeviceEvent.typeCodeCancelled => (LucideIcons.x, AppColors.ink45),
      KidDeviceEvent.typeDeviceRevoked => (
        LucideIcons.trash2,
        AppColors.dangerFg,
      ),
      _ => (LucideIcons.circle, AppColors.ink45),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DfCard(
        padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: Icon(icon, size: 15, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                event.label(),
                style: AppText.body(size: 13.5, color: AppColors.ink),
              ),
            ),
            const SizedBox(width: 8),
            Text(event.ageLabel(DateTime.now()), style: AppText.caption()),
          ],
        ),
      ),
    );
  }
}
