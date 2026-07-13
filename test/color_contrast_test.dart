import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/theme/app_theme.dart';

/// WCAG 2.1 contrast verification for the kid app's UI colors.
///
/// WCAG 2.1 distinguishes between:
///   - Normal text (< 18pt, < 14pt bold): requires 4.5:1
///   - Large text (≥ 18pt, ≥ 14pt bold): requires 3:1
///   - Graphical elements / UI icons (≥ 24px / 48dp): requires 3:1
///
/// Why this matters: the kid app's LockedScreen shows a big white
/// countdown on a green background. If that combo fails WCAG AA
/// for body text, a kid with low vision literally can't read how
/// much time they have left. Same for the UnlockedScreen — if
/// "All clear" doesn't pop, the kid won't notice the lock is off.
///
/// We check the actual foreground/background pairs each screen
/// uses, with the appropriate threshold per element type. If you
/// add a new screen or recolor an existing one, add the new pair
/// here.
void main() {
  group('WCAG AA: LockedScreen body text (4.5:1 required)', () {
    // The LockedScreen has white text on the grassDeep background
    // for body-sized labels (16pt, 14pt). The big timer is 72pt
    // (covered in the next group, 3:1 is enough).
    test('white on grassDeep passes 4.5:1 for body text', () {
      final ratio = contrastRatio(Colors.white, AppColors.grassDeep);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason:
            'white body text on LockedScreen needs 4.5:1; '
            'actual=$ratio',
      );
    });

    test('grassDeep is dark enough that white text passes 4.5:1 '
        'even at 14pt', () {
      // If this ever drops below 4.5:1, every body text element
      // on the LockedScreen ("Ask for a break" label, "until X
      // min target", "Sent — waiting…") becomes unreadable for
      // kids with low vision. This test is the tripwire.
      final ratio = contrastRatio(Colors.white, AppColors.grassDeep);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason:
            'grassDeep must stay contrast-friendly; '
            'actual=$ratio',
      );
    });
  });

  group('WCAG AA: LockedScreen big elements (3:1 required)', () {
    test('white on grass passes 3:1 for the big timer', () {
      // The 72pt HH:MM:SS timer is "large text" by WCAG. The
      // bright grass color (vs the deeper LockedScreen background
      // grassDeep) is used here only as a reference — actual
      // background is grassDeep. We keep this test as a reminder
      // that the bright grass accent does NOT support body text.
      final ratio = contrastRatio(Colors.white, AppColors.grass);
      expect(
        ratio,
        greaterThanOrEqualTo(3.0),
        reason:
            'white on bright grass must pass 3:1 for large '
            'text/icons; actual=$ratio',
      );
    });

    test('white on grassDeep passes 3:1 for the big timer', () {
      final ratio = contrastRatio(Colors.white, AppColors.grassDeep);
      expect(
        ratio,
        greaterThanOrEqualTo(3.0),
        reason:
            'big timer on LockedScreen must pass 3:1; '
            'actual=$ratio',
      );
    });
  });

  group('WCAG AA: UnlockedScreen body text (4.5:1 required)', () {
    test('kidInk on kidBg passes 4.5:1 for body text', () {
      final ratio = contrastRatio(AppColors.kidInk, AppColors.kidBg);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason:
            '"All clear" body text must pass 4.5:1; '
            'actual=$ratio',
      );
    });

    test('kidInk on card passes 4.5:1 for the "Nice work" chip', () {
      final ratio = contrastRatio(AppColors.kidInk, AppColors.card);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason:
            '"Nice work staying focused" chip text on white '
            'card must pass 4.5:1; actual=$ratio',
      );
    });
  });

  group('WCAG AA: status chip icons (3:1 required for graphics)', () {
    // 48dp+ Lucide icons on pale fills. WCAG 1.4.11 only requires
    // 3:1 for non-text contrast.
    test('ok icon on okFill passes 3:1', () {
      final ratio = contrastRatio(AppColors.ok, AppColors.okFill);
      expect(
        ratio,
        greaterThanOrEqualTo(3.0),
        reason:
            'UnlockedScreen check icon must pass 3:1; '
            'actual=$ratio',
      );
    });

    test('warn icon on warnFill passes 3:1', () {
      final ratio = contrastRatio(AppColors.warn, AppColors.warnFill);
      expect(
        ratio,
        greaterThanOrEqualTo(3.0),
        reason:
            'WaitingScreen wifi icon must pass 3:1; '
            'actual=$ratio',
      );
    });

    test('danger icon on dangerFill passes 3:1', () {
      final ratio = contrastRatio(AppColors.danger, AppColors.dangerFill);
      expect(
        ratio,
        greaterThanOrEqualTo(3.0),
        reason: 'danger status icon must pass 3:1; actual=$ratio',
      );
    });
  });

  group('WCAG AA: WaitingScreen body text (4.5:1 required)', () {
    test('ink on paper passes 4.5:1 for the body paragraph', () {
      final ratio = contrastRatio(AppColors.ink, AppColors.paper);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason:
            'WaitingScreen body text on paper must pass 4.5:1; '
            'actual=$ratio',
      );
    });

    test('ink on warnFill passes 4.5:1 for warning body text', () {
      // The warning title bar / chip copy is body-sized.
      final ratio = contrastRatio(AppColors.ink, AppColors.warnFill);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: 'warning body text must pass 4.5:1; actual=$ratio',
      );
    });
  });

  group('AAA-grade: paper background with ink text', () {
    test('paper background achieves AAA (7:1) with ink', () {
      // Documenting that the default body text on the default
      // background passes the strictest WCAG tier. If a future
      // redesign weakens this, the test catches it.
      final ratio = contrastRatio(AppColors.ink, AppColors.paper);
      expect(
        ratio,
        greaterThanOrEqualTo(7.0),
        reason:
            'paper + ink is the default text combination; '
            'should be AAA. actual=$ratio',
      );
    });
  });
}

/// Computes the WCAG 2.1 contrast ratio between two colors.
///
/// Algorithm: convert each sRGB channel to linear via the WCAG
/// gamma function, compute relative luminance L = 0.2126R +
/// 0.7152G + 0.0722B, then ratio = (L_bright + 0.05) / (L_dark +
/// 0.05). Returns a value in [1.0, 21.0].
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final bright = la > lb ? la : lb;
  final dark = la > lb ? lb : la;
  return (bright + 0.05) / (dark + 0.05);
}

double relativeLuminance(Color c) {
  final r = channelToLinear(c.r);
  final g = channelToLinear(c.g);
  final bl = channelToLinear(c.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * bl;
}

/// WCAG 2.x sRGB → linear. Below 0.03928 (in the gamma-
/// compressed sRGB space) the curve is linear; above it the
/// curve is a 2.4-power gamma. The piecewise definition is
/// defined in WCAG 2.x §1.4.3.
double channelToLinear(double v) {
  if (v <= 0.03928) {
    return v / 12.92;
  }
  return math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}
