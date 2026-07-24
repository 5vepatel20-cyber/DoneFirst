import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';

/// Splash + entry-point. Full-bleed celebratory green gradient (the same
/// radial used on the kid "unlocked" moment), centered brand mark,
/// wordmark, tagline, and a small pulsing loader near the bottom.
///
/// Used by `EntryPoint` in `main.dart` while auth state is being
/// resolved. The auth check itself still runs in `EntryPoint` —
/// this widget is purely visual.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Hardcoded scaffold + gradient so the splash always reads as the
    // green celebratory brand moment regardless of light/dark mode.
    return Scaffold(
      backgroundColor: AppColors.kidGradBottom,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.1,
            colors: [AppColors.kidGradTop, AppColors.kidGradBottom],
          ),
        ),
        child: Stack(
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
                    style: AppText.display(size: 34, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Do the work. Earn the rest.',
                    style: AppText.body(
                      size: 14,
                      w: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.82),
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
                  color: Colors.white.withValues(alpha: opacity),
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
