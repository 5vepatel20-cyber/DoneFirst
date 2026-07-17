import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/break_service.dart';
import '../../services/kid_realtime_service.dart';
import '../../theme/app_theme.dart';

/// Shown when there's an active homework_sessions row with
/// status='active' for this kid device.
///
/// Big timer ticks down toward the session's natural end (computed
/// from started_at + min_lock_minutes). The "Ask for a break"
/// button inserts a break_requests row which the parent app picks
/// up via its realtime listener.
///
/// Minimalist on purpose — no tasks, no proofs, no streaks. Those
/// stay on the parent's device in v1.
class LockedScreen extends StatefulWidget {
  final HomeworkSessionPayload session;
  final String childName;
  final VoidCallback onBreakRequestSent;

  const LockedScreen({
    super.key,
    required this.session,
    required this.childName,
    required this.onBreakRequestSent,
  });

  @override
  State<LockedScreen> createState() => _LockedScreenState();
}

class _LockedScreenState extends State<LockedScreen> {
  final _breakService = BreakService();
  Timer? _tick;
  bool _sendingBreak = false;
  bool _breakSent = false;

  @override
  void initState() {
    super.initState();
    // Re-render every second so the countdown updates. The state
    // machine in KidRealtimeService still owns the truth; this is
    // just a visual ticking.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Time remaining on the lock. Clamped at 0 (the parent UI shows
  /// its own countdown that may run longer if the parent extends
  /// mid-flight).
  Duration get _remaining {
    final endsAt = widget.session.startedAt.add(
      Duration(minutes: widget.session.minLockMinutes),
    );
    final now = DateTime.now();
    final diff = endsAt.difference(now);
    return diff.isNegative ? Duration.zero : diff;
  }

  Future<void> _askForBreak() async {
    if (_sendingBreak || _breakSent) return;
    setState(() => _sendingBreak = true);
    try {
      await _breakService.requestBreak(
        widget.session.id,
        widget.session.childId,
      );
      if (!mounted) return;
      setState(() {
        _breakSent = true;
        _sendingBreak = false;
      });
      widget.onBreakRequestSent();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendingBreak = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send break request: $e')),
      );
    }
  }

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int n) => n.toString().padLeft(2, '0');
    if (h > 0) return '${two(h)}:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining;
    return Scaffold(
      // grassDeep (not grass) because white body text on grass
      // fails WCAG AA at 4.5:1 (only ~3.4:1). See
      // test/color_contrast_test.dart and AppColors.grassDeep.
      backgroundColor: AppColors.grassDeep,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.lock,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Time for ${widget.childName}',
                  style: AppText.body(
                    color: Colors.white.withValues(alpha: 0.85),
                    size: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Locked in for homework',
                  style: AppText.title(color: Colors.white, size: 24),
                ),
                const SizedBox(height: 36),
                Text(
                  _format(remaining),
                  style: AppText.bigTimer(color: Colors.white, size: 72),
                ),
                const SizedBox(height: 16),
                Text(
                  'until ${widget.session.minLockMinutes} min target',
                  style: AppText.body(
                    color: Colors.white.withValues(alpha: 0.85),
                    size: 14,
                  ),
                ),
                const SizedBox(height: 56),
                if (_breakSent)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.check,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Sent — waiting for your parent',
                          style: AppText.body(color: Colors.white, size: 14),
                        ),
                      ],
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _sendingBreak ? null : _askForBreak,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: _sendingBreak
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(LucideIcons.hand, size: 18),
                    label: const Text('Ask for a break'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
