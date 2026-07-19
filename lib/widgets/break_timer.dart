import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';

class BreakTimer extends StatefulWidget {
  final int breakDurationSeconds;
  final VoidCallback onComplete;
  final VoidCallback? onCancel;

  const BreakTimer({
    super.key,
    this.breakDurationSeconds = 300,
    required this.onComplete,
    this.onCancel,
  });

  @override
  State<BreakTimer> createState() => _BreakTimerState();
}

class _BreakTimerState extends State<BreakTimer> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.breakDurationSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining <= 1) {
        _timer?.cancel();
        widget.onComplete();
        return;
      }
      setState(() => _remaining--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _formatted {
    final min = _remaining ~/ 60;
    final sec = _remaining % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _remaining / widget.breakDurationSeconds;
    return Card(
      color: AppColors.info.withValues(alpha:0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(LucideIcons.coffee, color: AppColors.info),
                const SizedBox(width: 8),
                const Text(
                  'Break Time!',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.info,
                  ),
                ),
                const Spacer(),
                if (widget.onCancel != null)
                  TextButton(
                    onPressed: () {
                      _timer?.cancel();
                      widget.onCancel!();
                    },
                    child: const Text('End Break Early'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: AppColors.info.withValues(alpha:0.1),
                  color: AppColors.info,
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _formatted,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                color: AppColors.info,
              ),
            ),
            const Text(
              'Apps will re-lock automatically when timer ends',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
