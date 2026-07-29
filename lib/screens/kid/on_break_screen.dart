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
  /// or break_ends_at. Prefer break_ends_at (the parent-stamped
  /// expiry) when available, falling back to started_at + duration.
  int _initialRemaining() {
    final expires = widget.activeBreak.breakEndsAt;
    if (expires != null) {
      final left = expires.difference(DateTime.now()).inSeconds;
      return left > 0 ? left : 0;
    }
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
      // Warm paper (not grass) because the kid is "free" right now;
      // a full green background would visually conflict with the
      // LockedScreen. The break icon + amber color carry the
      // "temporary" meaning.
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                    color: AppColors.amberTint,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    LucideIcons.coffee,
                    size: 42,
                    color: AppColors.amber,
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  'Take 5, ${widget.childName}',
                  textAlign: TextAlign.center,
                  style: AppText.title(size: 26),
                ),
                const SizedBox(height: 10),
                Text(
                  'A parent approved a short break. Your apps are open '
                  'while the timer runs.',
                  textAlign: TextAlign.center,
                  style: AppText.body(size: 15),
                ),
                const SizedBox(height: 32),
                // ── Break countdown card ──────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 24,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.borderCol),
                    boxShadow: AppShadows.card,
                  ),
                  child: Column(
                    children: [
                      Text(
                        _format(_remaining),
                        style: AppText.bigTimer(
                          color: AppColors.amberDeep,
                          size: 60,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'until break ends',
                        style: AppText.bodySecondary(size: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.lock,
                      size: 14,
                      color: AppColors.ink45,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Apps re-lock automatically when the break ends',
                      style: AppText.bodySecondary(size: 12.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
