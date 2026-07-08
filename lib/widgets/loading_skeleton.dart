import 'package:flutter/material.dart';

class LoadingSkeleton extends StatefulWidget {
  final int itemCount;
  final double height;
  final EdgeInsets padding;

  const LoadingSkeleton({
    super.key,
    this.itemCount = 3,
    this.height = 100,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(begin: 0.4, end: 0.8).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (ctx, _) {
        return ListView.builder(
          padding: widget.padding,
          itemCount: widget.itemCount,
          itemBuilder: (ctx, i) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              height: widget.height,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha:_animation.value),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        );
      },
    );
  }
}
