import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';

/// Parent-facing celebration shown after a homework session ends.
///
/// This screen is the parent's mirror moment: after `_unlock()` on the
/// lock-active screen, the parent sees a focused confirmation of what
/// just happened (how long the kid studied, how many tasks were
/// approved, the new streak) before returning to the dashboard.
///
/// Calmer than the kid version — a warm summary card on paper, not a
/// full-bleed party. The parent is the witness, not the celebrant.
///
/// Pass `minutesStudied`, `tasksCompleted`, and `streakDays` directly —
/// the screen does no data fetching, so it renders even if the
/// dashboard's other queries are still in flight.
class SessionCompleteParentScreen extends StatefulWidget {
  final String childName;
  final int minutesStudied;
  final int tasksCompleted;
  final int streakDays;
  final VoidCallback? onDone;

  const SessionCompleteParentScreen({
    super.key,
    required this.childName,
    required this.minutesStudied,
    required this.tasksCompleted,
    required this.streakDays,
    this.onDone,
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

  void _done() {
    if (widget.onDone != null) {
      widget.onDone!();
      return;
    }
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushNamedAndRemoveUntil('/dashboard', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    // Only surface stats we actually have — the summary shouldn't
    // invent a missing fact.
    final stats = <({String value, String caption, Color? color})>[
      if (widget.minutesStudied > 0)
        (value: '${widget.minutesStudied}m', caption: 'studied', color: null),
      if (widget.tasksCompleted > 0)
        (
          value: '${widget.tasksCompleted}',
          caption: widget.tasksCompleted == 1
              ? 'task approved'
              : 'tasks approved',
          color: null,
        ),
      if (widget.streakDays > 0)
        (
          value: '${widget.streakDays}',
          caption: 'day streak',
          color: AppColors.amberDeep,
        ),
    ];

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (_, _) => CustomPaint(
                  painter: _ConfettiPainter(controller: _controller),
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                child: DfCard(
                  padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppColors.greenTint,
                          borderRadius: BorderRadius.circular(AppRadius.tile),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          LucideIcons.check,
                          size: 38,
                          color: AppColors.green,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Homework complete',
                        textAlign: TextAlign.center,
                        style: AppText.title(size: 24),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.childName.isEmpty
                            ? 'Apps are unlocked'
                            : '${widget.childName} is free to go',
                        textAlign: TextAlign.center,
                        style: AppText.body(size: 14),
                      ),
                      if (stats.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: AppColors.paper,
                            borderRadius: BorderRadius.circular(AppRadius.tile),
                            border: Border.all(color: AppColors.borderCol),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              for (var i = 0; i < stats.length; i++) ...[
                                if (i > 0)
                                  Container(
                                    width: 1,
                                    height: 34,
                                    color: AppColors.border2,
                                  ),
                                Expanded(
                                  child: DfStatTile(
                                    stats[i].value,
                                    stats[i].caption,
                                    valueColor: stats[i].color,
                                    align: CrossAxisAlignment.center,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      DfButton(
                        'Done',
                        icon: LucideIcons.check,
                        onPressed: _done,
                      ),
                    ],
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

/// Parent-side confetti — seeded petal positions, drift phase offset,
/// rotation per petal — with a calm palette and few petals so it reads
/// as "well done", not fireworks.
class _ConfettiPainter extends CustomPainter {
  final Animation<double> controller;
  _ConfettiPainter({required this.controller}) : super(repaint: controller);

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
    AppColors.green,
    AppColors.amber,
    AppColors.greenBright,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final progress = controller.value;
    if (progress >= 1.0) return; // Confetti vanishes once landed.

    for (final p in _petals) {
      final startY = -20.0;
      final endY = size.height + 20.0;
      final y =
          startY +
          (endY - startY) * (progress + p.drift) % 1.0 * (endY - startY);
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
  final double x; // 0..1 of width
  final double drift; // 0..0.13 phase offset
  final double rotationSpeed;
  final int size; // px
  final int paletteIndex;

  _Confetti({
    required this.x,
    required this.drift,
    required this.rotationSpeed,
    required this.size,
    required this.paletteIndex,
  });
}
