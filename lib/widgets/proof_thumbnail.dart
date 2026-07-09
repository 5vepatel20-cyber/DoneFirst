import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Renders a proof-of-work photo with consistent placeholder / error /
/// loading states. Use everywhere a signed proof URL is displayed —
/// signed URLs expire after 7 days, and a broken-image icon is the
/// wrong UX for that case.
class ProofThumbnail extends StatelessWidget {
  final String url;
  final double height;
  final double? width;
  final BoxFit fit;
  final BorderRadius borderRadius;

  const ProofThumbnail({
    super.key,
    required this.url,
    this.height = 150,
    this.width = double.infinity,
    this.fit = BoxFit.cover,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Image.network(
        url,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (ctx, err, stack) => Container(
          height: height,
          width: width,
          color: AppColors.border.withValues(alpha: 0.2),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.broken_image_outlined,
                size: 32,
                color: AppColors.textSecondary,
              ),
              SizedBox(height: 4),
              Text(
                'Photo no longer available',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        loadingBuilder: (ctx, child, progress) {
          if (progress == null) return child;
          return Container(
            height: height,
            width: width,
            color: AppColors.border.withValues(alpha: 0.1),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
      ),
    );
  }
}