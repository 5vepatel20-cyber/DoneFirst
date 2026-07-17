import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/kid_realtime_service.dart';
import '../../theme/app_theme.dart';

/// Shown when there's an active homework session AND a parent-
/// approved break. Same enforcement as `UnlockedScreen` (no app
/// block, no kiosk lock) but the UI tells the kid they're on a
/// break, not free, and shows a soft countdown until the parent
/// ends the break.
///
/// The countdown is best-effort: the parent app's BreakTimer is
/// the source of truth, and the kid will be re-locked the moment
/// the parent persists `status='completed'` (or 'cancelled') and
/// the realtime subscription picks it up. We display a local
/// estimate so the kid has a sense of "5 min" even if the network
/// is mid-blip; if the realtime event arrives before our local
/// countdown expires, the screen swaps to LockedScreen before the
/// timer hits zero.
class OnBreakScreen extends StatefulWidget {
  final String childName;
  final BreakRequestPayload activeBreak;
  final int breakDurationSeconds;

  const OnBreakScreen({
    super.key,
    required this.childName,
    required this.activeBreak,
    this.breakDurationSeconds = 300,
  });

  @override
  State<OnBreakScreen> createState() => _OnBreakScreenState();
}

class _OnBreakScreenState extends State<OnBreakScreen> {
  Timer? _tick;
  late int _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = _initialRemaining();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remaining > 0) _remaining--;
      });
    });
  }

  /// Compute the initial countdown from the break's started_at
  /// + the parent's configured break duration. We don't pull
  /// the duration from the row because the parent app's
  /// BreakTimer is hardcoded to 5 min; the contract is "the kid
  /// app also assumes 5 min". If a future build changes the
  /// parent's break length, pass a different value here.
  int _initialRemaining() {
    final started = widget.activeBreak.startedAt;
    if (started == null) return widget.breakDurationSeconds;
    final elapsed = DateTime.now().difference(started).inSeconds;
    final left = widget.breakDurationSeconds - elapsed;
    return left > 0 ? left : 0;
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _format(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Use kidBg (not grass) because the kid is "free" right now;
      // a grass background would visually conflict with the
      // LockedScreen. The break icon + amber color carry the
      // "temporary" meaning.
      backgroundColor: AppColors.kidBg,
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
                    color: AppColors.warnFill,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.coffee,
                    size: 48,
                    color: AppColors.warn,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Take 5, ${widget.childName}',
                  textAlign: TextAlign.center,
                  style: AppText.title(size: 26),
                ),
                const SizedBox(height: 12),
                Text(
                  "Your parent approved a short break. Apps are "
                  'unlocked while the timer runs.',
                  textAlign: TextAlign.center,
                  style: AppText.bodySecondary(size: 15),
                ),
                const SizedBox(height: 36),
                Text(
                  _format(_remaining),
                  style: AppText.bigTimer(
                    color: AppColors.warn,
                    size: 64,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'until break ends',
                  style: AppText.bodySecondary(size: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
