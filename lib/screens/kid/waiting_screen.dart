import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/heartbeat_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/df_kit.dart';
import 'kid_settings_button.dart';

/// Why the kid app can't show them anything right now.
///
/// These were one screen, and that was the bug. A device still
/// subscribing (normal, resolves in a second or two) and a device whose
/// session is gone for good (needs a parent and a new pairing code)
/// both rendered the same sentence — "Waiting for your next session to
/// start" — which is reassuring, unactionable, and in the second case
/// simply false. A kid could sit in front of it indefinitely with no
/// hint that anyone needed to do anything.
enum KidWaitingReason {
  /// Paired and authenticated; realtime just hasn't reported a lock
  /// state yet. Expected on every cold launch. Self-resolving.
  connecting,

  /// Paired, but the Supabase client has no kid session — every read
  /// goes out as anon and comes back `200 []`. Nothing here is
  /// recoverable by waiting: the stored refresh token has usually been
  /// rotated away, and a parent has to re-pair the device.
  disconnected,
}

/// Shown when the kid app cannot honestly render a data screen.
///
/// It always states the one thing a kid actually cares about — their
/// apps are open and nothing is locked — because the alternative is a
/// kid assuming they're in trouble. It never claims to know anything
/// about their homework, since in this state we can't read any of it.
class WaitingScreen extends StatefulWidget {
  final VoidCallback onReconnect;
  final HeartbeatService heartbeat;

  /// Name of the paired child, for the settings sheet. Optional so
  /// the reconnect-race call path can omit it.
  final String? childName;

  /// Escape hatch: unpair the device from this stuck state. When
  /// null the settings gear is hidden.
  final Future<void> Function()? onUnpair;

  final KidWaitingReason reason;

  const WaitingScreen({
    super.key,
    required this.onReconnect,
    required this.heartbeat,
    this.childName,
    this.onUnpair,
    this.reason = KidWaitingReason.connecting,
  });

  @override
  State<WaitingScreen> createState() => _WaitingScreenState();
}

class _WaitingScreenState extends State<WaitingScreen> {
  Timer? _poll;
  Timer? _escalate;

  /// True once we've been trying long enough that "connecting" has
  /// stopped being a credible story.
  bool _stuck = false;

  /// A cold launch on a slow network legitimately takes a few seconds.
  /// Past this, silence is not reassurance — it's withholding.
  static const Duration _escalateAfter = Duration(seconds: 25);

  @override
  void initState() {
    super.initState();
    // Every 5s, force a heartbeat. Its success doesn't prove the
    // realtime channel is back, but it does bump last_seen_at, which
    // turns the parent's device dot green — so a parent looking at
    // their dashboard can see the kid's device is alive even while the
    // kid is stuck here. onReconnect re-attempts the subscription.
    _poll = Timer.periodic(
      const Duration(seconds: 5),
      (_) => widget.heartbeat.sendOnce().then((_) {
        if (mounted) widget.onReconnect();
      }),
    );
    if (widget.reason == KidWaitingReason.connecting) {
      _escalate = Timer(_escalateAfter, () {
        if (mounted) setState(() => _stuck = true);
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _escalate?.cancel();
    super.dispose();
  }

  /// Disconnected from the start, or connecting for long enough that
  /// it amounts to the same thing.
  bool get _showDisconnected =>
      widget.reason == KidWaitingReason.disconnected || _stuck;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Stack(
          children: [
            if (widget.onUnpair != null)
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4, top: 4),
                  child: KidSettingsButton(
                    childName: widget.childName ?? 'this device',
                    onUnpair: widget.onUnpair!,
                  ),
                ),
              ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                child: _showDisconnected
                    ? _disconnected()
                    : _connecting(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Connecting: calm, transient, no call to action ────────────────
  Widget _connecting() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _halo(LucideIcons.leaf, AppColors.greenTint, AppColors.green),
        const SizedBox(height: 28),
        Text(
          'Getting things ready',
          textAlign: TextAlign.center,
          style: AppText.title(size: 26),
        ),
        const SizedBox(height: 12),
        Text(
          'Checking in with your parent’s app. This only takes a moment.',
          textAlign: TextAlign.center,
          style: AppText.body(size: 15),
        ),
        const SizedBox(height: 28),
        _spinnerPill('Connecting…'),
      ],
    );
  }

  // ── Disconnected: honest, and says who has to do what ─────────────
  Widget _disconnected() {
    final name = widget.childName;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _halo(LucideIcons.wifiOff, AppColors.amberTint, AppColors.amberDeep),
        const SizedBox(height: 28),
        Text(
          'Can’t reach your parent’s app',
          textAlign: TextAlign.center,
          style: AppText.title(size: 26),
        ),
        const SizedBox(height: 12),
        Text(
          name == null
              ? 'We can’t load anything right now, so we won’t guess.'
              : 'We can’t load your homework or your streak right now, '
                    '$name — so we won’t guess at them.',
          textAlign: TextAlign.center,
          style: AppText.body(size: 15),
        ),
        const SizedBox(height: 22),
        // The reassurance a kid actually needs, stated plainly. Being
        // unable to reach the server is not a punishment state.
        DfCard(
          padding: const EdgeInsets.all(AppSpacing.cardPaddingKid),
          child: Row(
            children: [
              const Icon(
                LucideIcons.lockOpen,
                size: 20,
                color: AppColors.green,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Your apps are open. Nothing is locked while we’re '
                  'disconnected.',
                  style: AppText.bodySecondary(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        DfButton(
          'Try again',
          icon: LucideIcons.refreshCw,
          expand: false,
          onPressed: widget.onReconnect,
        ),
        const SizedBox(height: 18),
        // The step nobody was told about. A rotated refresh token can't
        // be recovered on the device, so without saying this the kid
        // waits forever on a screen that will never change.
        Text(
          'Still stuck? Ask a parent to open DoneFirst and pair this '
          'device again — it only takes a code.',
          textAlign: TextAlign.center,
          style: AppText.caption(),
        ),
        const SizedBox(height: 14),
        _spinnerPill('Still trying…'),
      ],
    );
  }

  Widget _halo(IconData icon, Color bg, Color fg) => Container(
    width: 92,
    height: 92,
    decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
    alignment: Alignment.center,
    child: Icon(icon, size: 44, color: fg),
  );

  Widget _spinnerPill(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      border: Border.all(color: AppColors.borderCol),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: AppColors.green,
          ),
        ),
        const SizedBox(width: 12),
        Text(label, style: AppText.bodySecondary(size: 13.5)),
      ],
    ),
  );
}
