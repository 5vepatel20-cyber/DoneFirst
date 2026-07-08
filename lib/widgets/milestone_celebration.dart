import 'dart:math';
import 'package:flutter/material.dart';
import '../services/milestone_service.dart';
import '../theme/app_theme.dart';

class MilestoneCelebration extends StatefulWidget {
  final MilestoneInfo milestone;
  final VoidCallback onDismiss;

  const MilestoneCelebration({
    super.key,
    required this.milestone,
    required this.onDismiss,
  });

  @override
  State<MilestoneCelebration> createState() => _MilestoneCelebrationState();
}

class _MilestoneCelebrationState extends State<MilestoneCelebration>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Stack(
        children: [
          if (widget.milestone.isSignificant)
            Positioned.fill(
              child: CustomPaint(
                painter: _ConfettiPainter(controller: _controller),
              ),
            ),
          Center(
            child: ScaleTransition(
              scale: _scaleAnim,
              child: GestureDetector(
                onTap: widget.onDismiss,
                child: Card(
                  color: AppColors.accent.withValues(alpha:0.95),
                  child: Container(
                    width: 280,
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.milestone.emoji,
                          style: const TextStyle(fontSize: 64),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.milestone.title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.milestone.message,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: widget.onDismiss,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Awesome!'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final Animation<double> controller;
  _ConfettiPainter({required this.controller}) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(42);
    final progress = controller.value;
    final paint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 30; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height * (1 - progress) + 20;
      final color = Color.fromRGBO(
        rng.nextInt(256),
        rng.nextInt(256),
        rng.nextInt(256),
        (1 - (y / size.height)).clamp(0.0, 0.8),
      );
      paint.color = color;
      final w = 6 + rng.nextDouble() * 6;
      final h = 4 + rng.nextDouble() * 4;
      final rotation = rng.nextDouble() * pi;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      canvas.drawRect(Rect.fromLTWH(-w / 2, -h / 2, w, h), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => true;
}
