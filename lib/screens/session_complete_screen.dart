import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/app_theme.dart';
import '../widgets/ring_timer.dart';

/// Celebratory full-screen shown when a homework session wraps.
/// Promoted from `widgets/session_complete_celebration.dart` (which
/// renders as an overlay) into a real route so the kid sees a
/// dedicated "all done!" moment rather than a popup over the lock
/// screen.
///
/// Layout follows the handoff:
///   - Full-progress 150px grass ring with a solid grass check disc
///     in the center
///   - "All done!" 30px Bricolage headline
///   - "Your apps are unlocked" body
///   - Two stat pills (studied minutes + streak with flame)
///   - Full-width grass "Back to home"
///   - Subtle confetti via a CustomPainter that animates over ~1s
class SessionCompleteScreen extends StatefulWidget {
  final String childName;
  final int tasksCompleted;
  final int streakDays;
  final int? minutesStudied;
  final VoidCallback onDone;

  const SessionCompleteScreen({
    super.key,
    required this.childName,
    required this.tasksCompleted,
    required this.streakDays,
    required this.onDone,
    this.minutesStudied,
  });

  @override
  State<SessionCompleteScreen> createState() => _SessionCompleteScreenState();
}

class _SessionCompleteScreenState extends State<SessionCompleteScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.kidBg,
      body: SafeArea(
        child: Stack(
          children: [
            // Confetti painter. Sits behind the content stack so the
            // ring + text read cleanly on top.
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (_, _) => CustomPaint(
                  painter: _ConfettiPainter(controller: _controller),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Ring + check disc. We stack the check icon on top
                  // of the ring rather than using RingTimer's child
                  // slot so the disc is full-opacity grass, not a
                  // tinted version of the progress color.
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      RingTimer.celebration(
                        progress: 1.0,
                        child: const SizedBox.shrink(),
                      ),
                      Container(
                        width: 78,
                        height: 78,
                        decoration: const BoxDecoration(
                          color: AppColors.grass,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          LucideIcons.check,
                          color: Colors.white,
                          size: 44,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Text(
                    'All done!',
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                      color: AppColors.kidInk,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your apps are unlocked',
                    style: AppText.bodySecondary(),
                  ),
                  const SizedBox(height: 22),
                  // Two stat pills side-by-side. The minutes pill is
                  // hidden if the caller didn't supply the value
                  // (back-compat with callers that don't have it).
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.minutesStudied != null)
                        _StatPill(
                          icon: LucideIcons.clock,
                          value: '${widget.minutesStudied} min',
                          label: 'studied',
                        ),
                      if (widget.minutesStudied != null &&
                          widget.streakDays > 0)
                        const SizedBox(width: 12),
                      if (widget.streakDays > 0)
                        _StatPill(
                          icon: LucideIcons.flame,
                          iconColor: AppColors.warnDot,
                          value: '${widget.streakDays}-day',
                          label: 'streak',
                        ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: 240,
                    child: FilledButton.icon(
                      onPressed: widget.onDone,
                      icon: const Icon(
                        LucideIcons.arrowLeft,
                        size: 16,
                      ),
                      label: const Text('Back to home'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.grass,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(44),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _StatPill({
    required this.icon,
    required this.value,
    required this.label,
    this.iconColor = AppColors.grass,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: AppColors.kidLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Text(
            value,
            style: AppText.listTitle(color: AppColors.kidInk),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppText.bodySecondary(size: 12),
          ),
        ],
      ),
    );
  }
}

/// Confetti — small rotating leaf/petal shapes drift down from the
/// top during the celebration. Lighter than the old star painter so
/// it doesn't compete with the ring; tints are pulled from the
/// sage/grass palette to stay on-brand.
class _ConfettiPainter extends CustomPainter {
  final Animation<double> controller;
  _ConfettiPainter({required this.controller}) : super(repaint: controller);

  // Deterministic seed-based positions so the confetti layout
  // doesn't shuffle between frames.
  static final List<_Confetti> _petals = List.generate(28, (i) {
    return _Confetti(
      x: (i * 73 + 17) % 100 / 100,
      drift: ((i * 31) % 13) / 100,
      rotationSpeed: ((i % 7) - 3) * 0.4,
      size: 5 + (i % 5),
      paletteIndex: i % 3,
    );
  });

  static const _palette = [
    AppColors.grass,
    AppColors.warnDot,
    AppColors.forest,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final progress = controller.value;
    if (progress >= 1.0) return; // Confetti vanishes once landed.

    for (final p in _petals) {
      final startY = -20.0;
      final endY = size.height + 20.0;
      final y = startY + (endY - startY) * (progress + p.drift) % 1.0 *
              (endY - startY);
      final x = p.x * size.width;
      final opacity = (1.0 - progress).clamp(0.0, 1.0) * 0.7;

      final paint = Paint()..color = _palette[p.paletteIndex].withValues(alpha: opacity);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(progress * 6.28 * p.rotationSpeed);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: p.size.toDouble(),
        height: p.size.toDouble() * 0.5,
      );
      canvas.drawOval(rect, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => true;
}

class _Confetti {
  final double x;            // 0..1 of width
  final double drift;        // 0..0.13 phase offset
  final double rotationSpeed;
  final int size;            // px
  final int paletteIndex;

  _Confetti({
    required this.x,
    required this.drift,
    required this.rotationSpeed,
    required this.size,
    required this.paletteIndex,
  });
}