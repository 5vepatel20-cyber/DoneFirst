import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';
import '../widgets/ring_timer.dart';

/// Parent-facing celebration shown after a homework session ends.
///
/// The kid side uses a `SessionCompleteCelebration` overlay from
/// inside the kid app — that path doesn't have a parent context.
/// This screen is the parent's mirror moment: after `_unlock()` on
/// the lock-active screen, the parent sees a focused confirmation
/// of what just happened (how long the kid studied, how many tasks
/// were approved, what the new streak is) before they go back to
/// the dashboard.
///
/// The visual is intentionally calmer than the kid version: sage
/// ring instead of grass, fewer confetti petals, paper background
/// rather than kidBg. The parent isn't the one who just finished
/// the homework — they're the witness, not the celebrant.
///
/// Pass `minutesStudied`, `tasksCompleted`, and `streakDays`
/// directly — the screen does no data fetching, so it can render
/// even if the dashboard's other queries are still in flight.
class SessionCompleteParentScreen extends StatefulWidget {
  final String childName;
  final int minutesStudied;
  final int tasksCompleted;
  final int streakDays;
  final VoidCallback onDone;

  const SessionCompleteParentScreen({
    super.key,
    required this.childName,
    required this.minutesStudied,
    required this.tasksCompleted,
    required this.streakDays,
    required this.onDone,
  });

  @override
  State<SessionCompleteParentScreen> createState() =>
      _SessionCompleteParentScreenState();
}

class _SessionCompleteParentScreenState
    extends State<SessionCompleteParentScreen>
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
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Stack(
          children: [
            // Parent-side confetti — sage/forest/warn petals, fewer
            // than the kid version so it doesn't read as a "party"
            // screen. The parent wants a beat of "well done" before
            // moving on, not fireworks.
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
                  // Forest ring + check disc. The center disc uses
                  // forest (parent primary) rather than grass (kid
                  // primary) so the screen reads as a parent
                  // surface at a glance.
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      RingTimer.celebration(
                        progress: 1.0,
                        progressColor: AppColors.forest,
                        trackColor: AppColors.sageSoft,
                        child: const SizedBox.shrink(),
                      ),
                      Container(
                        width: 78,
                        height: 78,
                        decoration: const BoxDecoration(
                          color: AppColors.forest,
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
                    'Homework complete',
                    style: GoogleFonts.bricolageGrotesque(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.childName.isEmpty
                        ? 'Apps are unlocked'
                        : '${widget.childName} is free to go',
                    style: AppText.bodySecondary(),
                  ),
                  const SizedBox(height: 22),
                  // Three stat pills. We render them in a Wrap so
                  // narrow widths collapse to two lines gracefully
                  // rather than overflowing. Each pill is hidden
                  // when its value is zero / unknown — the
                  // celebration shouldn't lie about a missing fact.
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      if (widget.minutesStudied > 0)
                        _StatPill(
                          icon: LucideIcons.clock,
                          value: '${widget.minutesStudied} min',
                          label: 'studied',
                        ),
                      if (widget.tasksCompleted > 0)
                        _StatPill(
                          icon: LucideIcons.checkCheck,
                          value: '${widget.tasksCompleted}',
                          label: widget.tasksCompleted == 1
                              ? 'task approved'
                              : 'tasks approved',
                        ),
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
                      label: const Text('Back to dashboard'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.forest,
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
    this.iconColor = AppColors.forest,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: AppColors.hair2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Text(
            value,
            style: AppText.listTitle(),
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

/// Parent-side confetti. Same mechanics as the kid version (seeded
/// petal positions, drift phase offset, rotation per petal) but
/// with a calmer palette and fewer petals so it doesn't read as a
/// party. Sage + forest + warn — pulled from the parent palette.
class _ConfettiPainter extends CustomPainter {
  final Animation<double> controller;
  _ConfettiPainter({required this.controller}) : super(repaint: controller);

  // Deterministic seed-based positions so the confetti layout
  // doesn't shuffle between frames.
  static final List<_Confetti> _petals = List.generate(18, (i) {
    return _Confetti(
      x: (i * 73 + 17) % 100 / 100,
      drift: ((i * 31) % 13) / 100,
      rotationSpeed: ((i % 7) - 3) * 0.4,
      size: 5 + (i % 5),
      paletteIndex: i % 3,
    );
  });

  static const _palette = [
    AppColors.forest,
    AppColors.warnDot,
    AppColors.sage,
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
      final opacity = (1.0 - progress).clamp(0.0, 1.0) * 0.5;

      final paint = Paint()
        ..color = _palette[p.paletteIndex].withValues(alpha: opacity);

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
