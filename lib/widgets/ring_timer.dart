import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// SVG-style progress ring used for the parent lock-active timer
/// (96px), kid focus-time countdown (196px), and session-complete
/// celebration (150px). Two arcs drawn with [Canvas.drawArc] and
/// rounded stroke caps so the progress "head" looks smooth rather
/// than pixel-cut. Center text slot hosts tabular Bricolage digits.
///
/// [progress] is 0..1; values outside that range are clamped. When
/// the timer is paused, [paused] tints the progress to the warn
/// palette so it's visually distinct from a live "still ticking"
/// ring.
class RingTimer extends StatelessWidget {
  final double progress;
  final double size;
  final double strokeWidth;
  final Color progressColor;
  final Color trackColor;
  final Color? centerColor;
  final Widget? child;

  /// Convenience constructor for the parent-side 96px timer card.
  const RingTimer.parent({
    super.key,
    required this.progress,
    this.size = 96,
    this.strokeWidth = 9,
    this.progressColor = AppColors.grass,
    this.trackColor = const Color(0xFFE3EADF),
    this.centerColor,
    this.child,
  }) : assert(progress >= 0 && progress <= 1);

  /// Kid home focus-time 196px ring.
  const RingTimer.kid({
    super.key,
    required this.progress,
    this.size = 196,
    this.strokeWidth = 13,
    this.progressColor = AppColors.grass,
    this.trackColor = const Color(0xFFD8ECDB),
    this.centerColor,
    this.child,
  }) : assert(progress >= 0 && progress <= 1);

  /// Celebration 150px ring (full progress, with check disc inside).
  const RingTimer.celebration({
    super.key,
    this.progress = 1.0,
    this.size = 150,
    this.strokeWidth = 12,
    this.progressColor = AppColors.grass,
    this.trackColor = const Color(0xFFD8ECDB),
    this.centerColor,
    this.child,
  }) : assert(progress >= 0 && progress <= 1);

  const RingTimer({
    super.key,
    required this.progress,
    this.size = 96,
    this.strokeWidth = 9,
    this.progressColor = AppColors.grass,
    this.trackColor = const Color(0xFFE3EADF),
    this.centerColor,
    this.child,
  }) : assert(progress >= 0 && progress <= 1);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: progress.clamp(0.0, 1.0),
          strokeWidth: strokeWidth,
          progressColor: progressColor,
          trackColor: trackColor,
        ),
        child: Center(
          child: DefaultTextStyle.merge(
            style: AppText.bigTimer(
              color: centerColor ?? progressColor,
              size: size * 0.21,
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color progressColor;
  final Color trackColor;

  _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.progressColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;

    // Track — full circle, soft tint
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    // Progress — drawn as an arc starting at 12 o'clock going CW.
    // Empty progress draws nothing; the track alone is the placeholder.
    if (progress > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
        rect,
        -math.pi / 2, // start at top
        2 * math.pi * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress ||
      old.progressColor != progressColor ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}