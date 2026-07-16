import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';

/// DoneFirst brand mark — a rounded-square tile with a sprout
/// glyph in the center. Used on the splash screen (large, dark
/// forest bg) and the sign-in screen (small, paper bg). The two
/// variants share the geometry; only the color treatment differs.
class BrandLogo extends StatelessWidget {
  final double size;
  final Color tileColor;
  final Color glyphColor;

  /// Splash-screen variant: 72px, slightly lighter forest tile, mint
  /// glyph. Sits centered on the dark forest scaffold.
  const BrandLogo.splash({super.key})
      : size = 72,
        tileColor = const Color(0xFF3B7355),
        glyphColor = const Color(0xFFC9E4D5);

  /// Sign-in variant: 36px, sageSoft tile, forest glyph. Sits
  /// inline next to the wordmark.
  const BrandLogo.signIn({super.key})
      : size = 36,
        tileColor = AppColors.sageSoft,
        glyphColor = AppColors.forest;

  const BrandLogo({
    super.key,
    required this.size,
    required this.tileColor,
    required this.glyphColor,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.22);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: radius,
      ),
      alignment: Alignment.center,
      child: Icon(
        LucideIcons.sprout,
        size: size * 0.48,
        color: glyphColor,
      ),
    );
  }
}