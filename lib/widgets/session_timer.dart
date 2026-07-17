import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/app_theme.dart';

class SessionTimer extends StatefulWidget {
  final DateTime sessionStart;
  final int durationMinutes;
  final int? minUnlockMinutes;
  final int? autoLiftMinutes;
  final bool paused;

  const SessionTimer({
    super.key,
    required this.sessionStart,
    required this.durationMinutes,
    this.minUnlockMinutes,
    this.autoLiftMinutes,
    this.paused = false,
  });

  @override
  State<SessionTimer> createState() => _SessionTimerState();
}

class _SessionTimerState extends State<SessionTimer> {
  Timer? _tick;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!widget.paused) setState(() => _now = DateTime.now());
    });
  }

  @override
  void didUpdateWidget(SessionTimer old) {
    super.didUpdateWidget(old);
    if (widget.paused != old.paused) {
      if (!widget.paused) {
        _tick?.cancel();
        _tick = Timer.periodic(const Duration(seconds: 1), (_) {
          setState(() => _now = DateTime.now());
        });
      }
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final endTime = widget.sessionStart.add(
      Duration(minutes: widget.durationMinutes),
    );
    final totalDuration = endTime.difference(widget.sessionStart);
    final elapsed = widget.sessionStart.isBefore(_now)
        ? _now.difference(widget.sessionStart)
        : Duration.zero;
    final remaining = widget.sessionStart.isBefore(_now)
        ? endTime.difference(_now)
        : endTime.difference(widget.sessionStart);

    final progress = totalDuration.inSeconds > 0
        ? (elapsed.inSeconds / totalDuration.inSeconds).clamp(0.0, 1.0)
        : 0.0;

    String remainingStr;
    if (widget.paused) {
      remainingStr = 'PAUSED';
    } else if (remaining.isNegative) {
      remainingStr = '00:00';
    } else {
      final hours = remaining.inHours;
      final mins = remaining.inMinutes.remainder(60);
      final secs = remaining.inSeconds.remainder(60);
      remainingStr = hours > 0
          ? '${hours}h ${mins.toString().padLeft(2, '0')}m'
          : '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }

    String statusText;
    Color statusColor;
    if (widget.paused) {
      statusText = 'Paused';
      statusColor = AppColors.warning;
    } else if (remaining.isNegative) {
      statusText = 'Session ended';
      statusColor = AppColors.textSecondary;
    } else if (progress < 0.5) {
      statusText = 'Studying...';
      statusColor = AppColors.success;
    } else if (progress < 0.85) {
      statusText = 'Almost done!';
      statusColor = AppColors.warning;
    } else {
      statusText = 'Time almost up!';
      statusColor = AppColors.danger;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: statusColor,
                  ),
                ),
                Text(
                  remainingStr,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: widget.paused
                  ? LinearProgressIndicator(
                      value: null,
                      minHeight: 8,
                      backgroundColor: AppColors.border,
                    )
                  : LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: AppColors.border,
                      valueColor: AlwaysStoppedAnimation(statusColor),
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Started ${_formatTime(widget.sessionStart)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  'Ends ${_formatTime(endTime)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            if (widget.minUnlockMinutes != null ||
                widget.autoLiftMinutes != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (widget.minUnlockMinutes != null)
                    _infoChip(
                      LucideIcons.lock,
                      'Min unlock: ${_formatTime(widget.sessionStart.add(Duration(minutes: widget.minUnlockMinutes!)))}',
                    ),
                  const SizedBox(width: 8),
                  if (widget.autoLiftMinutes != null &&
                      widget.autoLiftMinutes! > 0)
                    _infoChip(
                      LucideIcons.unlock,
                      'Auto-lift: ${_formatTime(widget.sessionStart.add(Duration(minutes: widget.autoLiftMinutes!)))}',
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha:0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11, color: AppColors.primary)),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:${dt.minute.toString().padLeft(2, '0')} $ampm';
  }
}
