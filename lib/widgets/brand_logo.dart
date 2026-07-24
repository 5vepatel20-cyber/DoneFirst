import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// DoneFirst brand mark — a rounded-square tile carrying a bold "D"
/// wordmark glyph. Used on the splash (large, on the green gradient)
/// and inline on the sign-in / account screens (small, on paper). The
/// two variants share the geometry; only the color treatment differs.
class BrandLogo extends StatelessWidget {
  final double size;
  final Color tileColor;
  final Color glyphColor;

  /// Splash-screen variant: 76px, white tile, emerald glyph. Sits on
  /// the celebratory green gradient.
  const BrandLogo.splash({super.key})
    : size = 76,
      tileColor = Colors.white,
      glyphColor = AppColors.green;

  /// Sign-in variant: 40px, emerald tile, white glyph. Sits inline
  /// next to the wordmark on paper.
  const BrandLogo.signIn({super.key})
    : size = 40,
      tileColor = AppColors.green,
      glyphColor = Colors.white;

  const BrandLogo({
    super.key,
    required this.size,
    required this.tileColor,
    required this.glyphColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: tileColor == Colors.white
            ? const [
                BoxShadow(
                  color: Color(0x2A0C3A22),
                  blurRadius: 24,
                  spreadRadius: -6,
                  offset: Offset(0, 10),
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        'D',
        style: GoogleFonts.bricolageGrotesque(
          fontSize: size * 0.56,
          height: 1.0,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
          color: glyphColor,
        ),
      ),
    );
  }
}
