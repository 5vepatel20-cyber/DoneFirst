import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/heartbeat_service.dart';
import '../../theme/app_theme.dart';

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
  const WaitingScreen({
    super.key,
    required this.onReconnect,
    required this.heartbeat,
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
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: AppColors.warnFill,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.wifi,
                    size: 56,
                    color: AppColors.warn,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  "Can't reach the parent app",
                  textAlign: TextAlign.center,
                  style: AppText.title(size: 24),
                ),
                const SizedBox(height: 12),
                Text(
                  'WiFi or the DoneFirst service dropped for a '
                  'moment. Lock is paused — check your WiFi '
                  'and we\'ll reconnect automatically.',
                  textAlign: TextAlign.center,
                  style: AppText.bodySecondary(size: 15),
                ),
                const SizedBox(height: 32),
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppColors.grass,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
