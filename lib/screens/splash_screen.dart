import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';

/// Splash + entry-point. Full-bleed forest background, centered logo
/// tile, wordmark, tagline, three-dot loader near the bottom. The
/// loader is a light pulse against the dark scaffold so it reads
/// clearly without competing with the logo.
///
/// Used by `EntryPoint` in `main.dart` while auth state is being
/// resolved. The auth check itself still runs in `EntryPoint` —
/// this widget is purely visual.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Hardcoded scaffold so we don't depend on the AppTheme paper
    // background — the splash is always the dark forest color
    // regardless of light/dark mode.
    return Scaffold(
      backgroundColor: AppColors.forestHover,
      body: Stack(
        children: [
          // Center column: logo, wordmark, tagline
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandLogo.splash(),
                const SizedBox(height: 22),
                Text(
                  'DoneFirst',
                  style: GoogleFonts.bricolageGrotesque(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.7,
                    color: const Color(0xFFF4F7F2),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Homework first. Apps after.',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF9FC3AC),
                  ),
                ),
              ],
            ),
          ),
          // Bottom-pinned 3-dot loader. Each dot pulses on its own
          // 1.2s cycle, offset by 200ms, so the motion feels
          // orchestrated rather than random.
          const Positioned(
            left: 0,
            right: 0,
            bottom: 56,
            child: Center(child: _ThreeDotLoader()),
          ),
        ],
      ),
    );
  }
}

/// Light status-bar overlay — the system bar (clock/battery) shows
/// in white so it remains visible against the dark scaffold. Apply
/// this to the splash route in `MaterialApp`.
class SplashSystemBar extends StatelessWidget {
  const SplashSystemBar({super.key});

  @override
  Widget build(BuildContext context) {
    return const AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: SizedBox.shrink(),
    );
  }
}

class _ThreeDotLoader extends StatefulWidget {
  const _ThreeDotLoader();

  @override
  State<_ThreeDotLoader> createState() => _ThreeDotLoaderState();
}

class _ThreeDotLoaderState extends State<_ThreeDotLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Each dot's opacity follows the controller value but
            // is offset by i * 0.33 of the cycle so the dots pulse
            // in sequence rather than together.
            final phase = (_controller.value + i * 0.33) % 1.0;
            final opacity = phase < 0.5
                ? 0.3 + (phase * 2) * 0.7
                : 0.3 + ((1 - phase) * 2) * 0.7;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFFC9E4D5).withValues(alpha: opacity),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}