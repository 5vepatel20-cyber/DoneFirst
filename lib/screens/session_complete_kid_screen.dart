import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_theme.dart';

/// Full-screen kid-side celebration shown when a homework session
/// ends (parent unlocks early, the lock timer runs out, or the
/// kid-side app reconnects after a long offline gap).
///
/// Promoted from the legacy `SessionCompleteCelebration` widget
/// (which was a Card overlay inside kid_home_screen) so the kid
/// gets a focused moment — no tasks list, no streak chip, no
/// distractions. The CTA pops the route back to the home screen.
///
/// Visual spec from the sage-forest handoff (README §17):
///   • 150px grass ring with a solid grass check disc in the center
///   • "All done!" 30px Bricolage
///   • "Your apps are unlocked"
///   • Two stat pills: studied minutes + flame streak
///   • Full-width grass "Back to home" CTA
///   • Subtle confetti + scale-in animation
class SessionCompleteKidScreen extends StatefulWidget {
  final String childName;
  final int tasksCompleted;
  final int streakDays;
  final int minutesStudied;

  const SessionCompleteKidScreen({
    super.key,
    required this.childName,
    required this.tasksCompleted,
    required this.streakDays,
    required this.minutesStudied,
  });

  @override
  State<SessionCompleteKidScreen> createState() =>
      _SessionCompleteKidScreenState();
}

class _SessionCompleteKidScreenState extends State<SessionCompleteKidScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _ringAnim;
  late final Animation<double> _checkAnim;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    // Ring grows from 0 → 1 over the first 700ms; the check disc
    // and labels come in slightly after so the ring "lands" first.
    _ringAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.65, curve: Curves.easeOutCubic),
    );
    _checkAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 1.0, curve: Curves.elasticOut),
    );
    _fadeAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
    );
    _scaleAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 1.0, curve: Curves.easeOutBack),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _backToHome() {
    // The screen was pushed on top of kid_home_screen — popping
    // returns the kid to their unlocked home view. pushAndRemoveUntil
    // isn't needed here because kid_root.dart wraps the entire flow
    // and the kid can still navigate within it.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // kidBg — slightly warmer green than paper, matches the
      // kid-side chrome in kid_home_screen / kid_history_screen.
      backgroundColor: AppColors.kidBg,
      body: SafeArea(
        child: Stack(
          children: [
            // Confetti layer behind the content. Lightweight CustomPainter
            // (no third-party deps) so the screen works without adding
            // a particle engine just for this celebratory moment.
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (_, _) => CustomPaint(
                  painter: _ConfettiPainter(progress: _controller.value),
                ),
              ),
            ),
            Center(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: ScaleTransition(
                  scale: _scaleAnim,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenPadding,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _CompletionRing(
                          ringProgress: _ringAnim,
                          checkProgress: _checkAnim,
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'All done!',
                          style: AppText.title(size: 30),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your apps are unlocked',
                          style: AppText.body(size: 15),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        _StatPills(
                          minutesStudied: widget.minutesStudied,
                          streakDays: widget.streakDays,
                        ),
                        const SizedBox(height: 36),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _backToHome,
                            icon: const Icon(
                              LucideIcons.arrowLeft,
                              size: 18,
                            ),
                            label: const Text('Back to home'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.grass,
                              foregroundColor: AppColors.card,
                              minimumSize: const Size.fromHeight(50),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.button),
                              ),
                              textStyle: AppText.button(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 150px grass-toned ring with a solid grass check disc that
/// scales in on top. Built as a CustomPainter so the ring's
/// start angle is animatable from 0 → 2π without rebuilding
/// the whole tree.
class _CompletionRing extends StatelessWidget {
  final Animation<double> ringProgress;
  final Animation<double> checkProgress;

  const _CompletionRing({
    required this.ringProgress,
    required this.checkProgress,
  });

  static const double _size = 150;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: AnimatedBuilder(
        animation: Listenable.merge([ringProgress, checkProgress]),
        builder: (_, _) => CustomPaint(
          painter: _RingPainter(
            progress: ringProgress.value,
            checkProgress: checkProgress.value,
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double checkProgress;

  _RingPainter({required this.progress, required this.checkProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 8;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Track — pale sage ring underneath the animated arc.
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = AppColors.kidLine;
    canvas.drawCircle(center, radius, track);

    // Animated grass arc, sweeping clockwise from 12 o'clock.
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = AppColors.grass;
    canvas.drawArc(
      rect,
      -pi / 2,
      progress * 2 * pi,
      false,
      arc,
    );

    // Solid check disc that pops in once the ring lands.
    if (checkProgress > 0) {
      final discRadius = radius - 18;
      final discPaint = Paint()..color = AppColors.grass;
      canvas.drawCircle(center, discRadius * checkProgress.clamp(0.0, 1.0),
          discPaint);

      if (checkProgress > 0.5) {
        // White check mark — drawn over the disc using two line
        // segments. Eases in with the disc so the whole shape
        // settles together.
        final checkPaint = Paint()
          ..color = AppColors.card
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        final s = discRadius * 0.55;
        final alpha = ((checkProgress - 0.5) / 0.5).clamp(0.0, 1.0);
        // Translate the two check segments relative to the disc
        // center so they form a tick.
        final p1 = center + Offset(-s * 0.55, s * 0.05);
        final p2 = center + Offset(-s * 0.15, s * 0.55);
        final p3 = center + Offset(s * 0.7, -s * 0.45);
        _drawCheckSegment(canvas, checkPaint, p1, p2, alpha);
        _drawCheckSegment(canvas, checkPaint, p2, p3, alpha);
      }
    }
  }

  /// Draws one segment of the check mark, fading in as `alpha`
  /// moves from 0 → 1. Splits the segment into a sub-segment so
  /// the visible portion grows from the start point rather than
  /// appearing all at once.
  void _drawCheckSegment(
    Canvas canvas,
    Paint paint,
    Offset from,
    Offset to,
    double alpha,
  ) {
    final t = alpha;
    final end = Offset.lerp(from, to, t)!;
    final faded = paint..color = paint.color.withValues(alpha: alpha);
    canvas.drawLine(from, end, faded);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.checkProgress != checkProgress;
}

/// Two side-by-side stat pills: "X min" and "🔥 N days" (with a
/// flame icon instead of an emoji, per the handoff).
class _StatPills extends StatelessWidget {
  final int minutesStudied;
  final int streakDays;

  const _StatPills({
    required this.minutesStudied,
    required this.streakDays,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Pill(
          icon: LucideIcons.timer,
          label: 'Studied',
          value: _formatMinutes(minutesStudied),
          tint: AppColors.grass,
        ),
        const SizedBox(width: 12),
        _Pill(
          icon: LucideIcons.flame,
          label: 'Streak',
          value: streakDays == 1
              ? '1 day'
              : '$streakDays days',
          tint: AppColors.warnDot,
        ),
      ],
    );
  }

  static String _formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color tint;

  const _Pill({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.kidCard),
        border: Border.all(color: AppColors.kidLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppText.bodySecondary(size: 11),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppText.cardHeader(size: 15),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cheap procedural confetti: 18 paper-thin colored shards that
/// drift down from the top with random rotation. Uses a fixed
/// seed so the kid sees the same pattern every launch (the seed
/// is mixed with the animation progress, not a re-roll each
/// frame).
class _ConfettiPainter extends CustomPainter {
  final double progress;

  _ConfettiPainter({required this.progress});

  static const _count = 18;
  static const _palette = <Color>[
    AppColors.grass,
    AppColors.warnDot,
    AppColors.gold,
    AppColors.forest,
    AppColors.sage,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final rng = Random(7);
    for (var i = 0; i < _count; i++) {
      // Each shard starts at a slightly different x with its own
      // fall speed + rotation rate so the shower feels organic
      // rather than lockstep.
      final startX = rng.nextDouble() * size.width;
      final speed = 0.6 + rng.nextDouble() * 0.8;
      final wobble = (rng.nextDouble() - 0.5) * 40;
      final y = (progress * speed * size.height) -
          20 +
          sin(progress * pi * 2 + i) * 12;
      final x = startX + wobble * progress;
      final color = _palette[i % _palette.length];
      final rot = progress * pi * (i.isEven ? 2 : -3);
      final shardSize = 6.0 + rng.nextDouble() * 6;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rot);
      final paint = Paint()..color = color.withValues(alpha: 0.85);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: shardSize,
            height: shardSize * 0.45,
          ),
          const Radius.circular(1.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) =>
      old.progress != progress;
}