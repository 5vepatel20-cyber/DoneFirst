import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/heartbeat_service.dart';
import '../../theme/app_theme.dart';
import 'kid_settings_button.dart';

/// Transient "Reconnecting…" state shown when:
///   - the realtime channel is currently disconnected (WiFi drop,
///     Supabase side outage, background TCP timeout), OR
///   - the most recent heartbeat returned 401 (kid device revoked).
///
/// Releases any active blocking immediately on this screen — a kid
/// stuck mid-session shouldn't be trapped behind a screen they can't
/// talk to. We keep polling heartbeat.sendOnce() on a short interval
/// so the moment the network comes back the parent UI flips green
/// again and the kid returns to whichever state they should be in.
class WaitingScreen extends StatefulWidget {
  final VoidCallback onReconnect;
  final HeartbeatService heartbeat;

  /// Name of the paired child, for the settings sheet. Optional so
  /// the reconnect-race call path can omit it.
  final String? childName;

  /// Escape hatch: unpair the device from this stuck state. When
  /// null the settings gear is hidden.
  final Future<void> Function()? onUnpair;

  const WaitingScreen({
    super.key,
    required this.onReconnect,
    required this.heartbeat,
    this.childName,
    this.onUnpair,
  });

  @override
  State<WaitingScreen> createState() => _WaitingScreenState();
}

class _WaitingScreenState extends State<WaitingScreen> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Every 5s, force a heartbeat. The success path of heartbeat
    // doesn't tell us the realtime channel is back — but it does
    // bump last_seen_at, which makes the parent's dot green. The
    // realtime listener itself will tell us when it's re-subscribed
    // and main.dart will swap to the right screen.
    _poll = Timer.periodic(
      const Duration(seconds: 5),
      (_) => widget.heartbeat.sendOnce().then((_) {
        if (mounted) widget.onReconnect();
      }),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

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
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: const BoxDecoration(
                        color: AppColors.greenTint,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        LucideIcons.leaf,
                        size: 44,
                        color: AppColors.green,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Hang tight',
                      textAlign: TextAlign.center,
                      style: AppText.title(size: 26),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Waiting for your next session to start — this "
                      'screen updates the moment it does. If the WiFi '
                      "dipped, we'll reconnect on our own.",
                      textAlign: TextAlign.center,
                      style: AppText.body(size: 15),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
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
                          Text(
                            'Checking for updates…',
                            style: AppText.bodySecondary(size: 13.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
