import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';

/// Full-screen kid-side celebration shown when a homework session
/// ends (parent unlocks early, the lock timer runs out, or the
/// kid-side app reconnects after a long offline gap).
///
/// Styled as the "Kid · Unlocked ✦" payoff: a warm green celebration
/// on the kid gradient — a white check ring lands, then "Approved.
/// You're free." with the session's stats and a single CTA. The CTA
/// pops the route back to the kid's home.
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
    // The screen was pushed on top of the kid home — popping returns
    // the kid to their unlocked home view. pushAndRemoveUntil isn't
    // needed because kid_root.dart wraps the entire flow and the kid
    // can still navigate within it.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.kidGradTop, AppColors.kidGradBottom],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Confetti layer behind the content.
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
                          const SizedBox(height: 30),
                          Text(
                            'Approved.',
                            textAlign: TextAlign.center,
                            style: AppText.display(
                              size: 38,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            "You're free.",
                            textAlign: TextAlign.center,
                            style: AppText.display(
                              size: 38,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Apps are unlocked. Nice work today.',
                            style: AppText.body(
                              size: 15,
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),
                          _StatsRow(
                            minutesStudied: widget.minutesStudied,
                            streakDays: widget.streakDays,
                            tasksCompleted: widget.tasksCompleted,
                          ),
                          const SizedBox(height: 34),
                          _DoneButton(onTap: _backToHome),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dark "Done — open my apps" button — reads clearly on the green
/// gradient with the signature `0 4px 0` bottom edge.
class _DoneButton extends StatelessWidget {
  final VoidCallback onTap;
  const _DoneButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(AppRadius.button),
          boxShadow: const [
            BoxShadow(color: Color(0xFF0E0C09), offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Done — open my apps', style: AppText.button()),
            const SizedBox(width: 8),
            const Icon(LucideIcons.arrowRight, size: 18, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

/// 150px white ring with a solid white check disc (green tick) that
/// scales in on top. Built as a CustomPainter so the ring's start
/// angle is animatable from 0 → 2π without rebuilding the tree.
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

    // Track — faint white ring underneath the animated arc.
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = Colors.white.withValues(alpha: 0.28);
    canvas.drawCircle(center, radius, track);

    // Animated white arc, sweeping clockwise from 12 o'clock.
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    canvas.drawArc(rect, -pi / 2, progress * 2 * pi, false, arc);

    // Solid white disc that pops in once the ring lands.
    if (checkProgress > 0) {
      final discRadius = radius - 18;
      final discPaint = Paint()..color = Colors.white;
      canvas.drawCircle(
        center,
        discRadius * checkProgress.clamp(0.0, 1.0),
        discPaint,
      );

      if (checkProgress > 0.5) {
        // Green check mark — drawn over the disc using two line
        // segments so it reads as the "approved" tick.
        final checkPaint = Paint()
          ..color = AppColors.green
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        final s = discRadius * 0.55;
        final alpha = ((checkProgress - 0.5) / 0.5).clamp(0.0, 1.0);
        final p1 = center + Offset(-s * 0.55, s * 0.05);
        final p2 = center + Offset(-s * 0.15, s * 0.55);
        final p3 = center + Offset(s * 0.7, -s * 0.45);
        _drawCheckSegment(canvas, checkPaint, p1, p2, alpha);
        _drawCheckSegment(canvas, checkPaint, p2, p3, alpha);
      }
    }
  }

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

/// Three glassy stat tiles: focused minutes, streak, tasks done.
class _StatsRow extends StatelessWidget {
  final int minutesStudied;
  final int streakDays;
  final int tasksCompleted;

  const _StatsRow({
    required this.minutesStudied,
    required this.streakDays,
    required this.tasksCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _GlassStat(
            value: _formatMinutes(minutesStudied),
            caption: 'focused',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _GlassStat(
            value: '$streakDays',
            caption: 'day streak',
            leadingIcon: LucideIcons.flame,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _GlassStat(
            value: '$tasksCompleted',
            caption: tasksCompleted == 1 ? 'task done' : 'tasks done',
          ),
        ),
      ],
    );
  }

  static String _formatMinutes(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

class _GlassStat extends StatelessWidget {
  final String value;
  final String caption;
  final IconData? leadingIcon;

  const _GlassStat({
    required this.value,
    required this.caption,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, size: 18, color: Colors.white),
                const SizedBox(width: 4),
              ],
              Text(
                value,
                style: AppText.statValue(size: 24, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: AppText.caption(color: Colors.white.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }
}

/// Cheap procedural confetti: 18 paper-thin shards drifting down from
/// the top with random rotation. Uses a fixed seed so the pattern is
/// stable (the seed is mixed with animation progress, not re-rolled).
class _ConfettiPainter extends CustomPainter {
  final double progress;

  _ConfettiPainter({required this.progress});

  static const _count = 18;
  static const _palette = <Color>[
    Colors.white,
    AppColors.amber,
    AppColors.gold,
    AppColors.greenTint,
    AppColors.amberTint,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final rng = Random(7);
    for (var i = 0; i < _count; i++) {
      final startX = rng.nextDouble() * size.width;
      final speed = 0.6 + rng.nextDouble() * 0.8;
      final wobble = (rng.nextDouble() - 0.5) * 40;
      final y =
          (progress * speed * size.height) -
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
