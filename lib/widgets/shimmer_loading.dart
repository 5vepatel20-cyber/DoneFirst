import 'package:flutter/material.dart';

class ShimmerLoading extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  final Color? baseColor;
  final Color? highlightColor;

  const ShimmerLoading({
    super.key,
    this.width = double.infinity,
    this.height = 20,
    this.borderRadius = 8,
    this.baseColor,
    this.highlightColor,
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = widget.baseColor ?? (isDark ? Colors.grey.shade800 : Colors.grey.shade300);
    final highlight = widget.highlightColor ?? (isDark ? Colors.grey.shade700 : Colors.grey.shade100);

    return AnimatedBuilder(
      animation: _controller,
      builder: (ctx, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              colors: [base, highlight, base],
              stops: const [0.0, 0.5, 1.0],
              transform: GradientRotation(_controller.value * 6.28),
            ),
          ),
        );
      },
    );
  }
}

class ShimmerCard extends StatelessWidget {
  final int lines;

  const ShimmerCard({super.key, this.lines = 3});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ShimmerLoading(width: 120, height: 16),
            const SizedBox(height: 12),
            ...List.generate(
              lines,
              (i) => Padding(
                padding: EdgeInsets.only(bottom: i < lines - 1 ? 8 : 0),
                child: ShimmerLoading(
                  width: double.infinity,
                  height: 14,
                  borderRadius: 4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardShimmer extends StatelessWidget {
  const DashboardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const ShimmerLoading(width: double.infinity, height: 40),
        const SizedBox(height: 12),
        const ShimmerCard(lines: 2),
        const SizedBox(height: 12),
        const ShimmerCard(lines: 1),
        const SizedBox(height: 12),
        const ShimmerCard(lines: 3),
      ],
    );
  }
}
