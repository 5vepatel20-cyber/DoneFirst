import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SessionCompleteCelebration extends StatefulWidget {
  final String childName;
  final int tasksCompleted;
  final int streakDays;
  final VoidCallback onDismiss;

  const SessionCompleteCelebration({
    super.key,
    required this.childName,
    required this.tasksCompleted,
    required this.streakDays,
    required this.onDismiss,
  });

  @override
  State<SessionCompleteCelebration> createState() =>
      _SessionCompleteCelebrationState();
}

class _SessionCompleteCelebrationState extends State<SessionCompleteCelebration>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
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
          Positioned.fill(
            child: CustomPaint(
              painter: _StarConfettiPainter(controller: _controller),
            ),
          ),
          Center(
            child: ScaleTransition(
              scale: _scaleAnim,
              child: GestureDetector(
                onTap: widget.onDismiss,
                child: Card(
                  color: AppColors.success.withOpacity(0.95),
                  child: Container(
                    width: 300,
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '🎉',
                          style: TextStyle(fontSize: 72),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Great job, ${widget.childName}!',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${widget.tasksCompleted} task${widget.tasksCompleted == 1 ? '' : 's'} completed',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white70,
                          ),
                        ),
                        if (widget.streakDays > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            '🔥 ${widget.streakDays}-day streak!',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: widget.onDismiss,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                          ),
                          child: const Text('Keep Going!'),
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

class _StarConfettiPainter extends CustomPainter {
  final Animation<double> controller;
  _StarConfettiPainter({required this.controller}) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(42);
    final progress = controller.value;
    final paint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 25; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height * (1 - progress) + 20;
      final color = Color.fromRGBO(
        rng.nextInt(256),
        rng.nextInt(256),
        rng.nextInt(256),
        (1 - (y / size.height)).clamp(0.0, 0.8),
      );
      paint.color = color;
      final s = 6 + rng.nextDouble() * 8;
      final rotation = rng.nextDouble() * pi;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      final path = Path()
        ..moveTo(s, 0)
        ..lineTo(s * 0.3, s * 0.3)
        ..lineTo(0, s)
        ..lineTo(-s * 0.3, s * 0.3)
        ..lineTo(-s, 0)
        ..lineTo(-s * 0.3, -s * 0.3)
        ..lineTo(0, -s)
        ..lineTo(s * 0.3, -s * 0.3)
        ..close();
      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _StarConfettiPainter old) => true;
}
