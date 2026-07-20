import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sage-forest design tokens. Replaces the old purple Material-3
/// palette with the redesign system from the handoff. Old names
/// (primary, success, danger, …) are preserved as aliases so the
/// 200+ existing references in screens/widgets don't have to
/// change in one pass — they repoint to the new hex values below.
class AppColors {
  // New sage-forest palette
  static const ink = Color(0xFF16201A);          // Primary text, near-black green
  static const ink2 = Color(0xFF5E6B62);         // Secondary text
  static const muted = Color(0xFF93A092);        // Tertiary text, icon-on-fill
  static const faint = Color(0xFFB4BBAF);        // Placeholder text
  static const hair = Color(0xFFE4E8DC);         // Device/section hairlines
  static const hair2 = Color(0xFFE1E6DA);        // Card & input borders
  static const line = Color(0xFFEEF1E9);         // Internal dividers
  static const paper = Color(0xFFF7F8F3);        // Parent scaffold background
  static const card = Color(0xFFFFFFFF);         // Card surface

  // Forest (parent primary)
  static const forest = Color(0xFF2E5A43);       // Primary buttons, brand
  static const forestHover = Color(0xFF274A38);  // Pressed/hover state
  static const deep = Color(0xFF21402F);         // Timer card, banner bg

  // Sage accent
  static const sage = Color(0xFF7FA98A);
  static const sageFill = Color(0xFFE2E9DD);     // Chips, info banners
  static const sageSoft = Color(0xFFDCE9DE);     // Parent monogram bg

  // Grass (kid primary)
  static const grass = Color(0xFF2F9E56);
  static const grassDeep = Color(0xFF257D44);  // LockedScreen bg (5.1:1 vs white)
  static const kidBg = Color(0xFFF1F8F0);
  static const kidLine = Color(0xFFCBE3CD);
  static const kidInk = Color(0xFF183F28);

  // Warm (warning / streak)
  static const warn = Color(0xFFB07C1E);
  static const warnDot = Color(0xFFE39A2B);      // Streak flame, locked dot
  static const warnFill = Color(0xFFFBF1DC);
  static const warnBd = Color(0xFFEAD8AC);

  // Danger
  static const danger = Color(0xFFB4503E);
  static const dangerFill = Color(0xFFF7E1DC);
  static const dangerBd = Color(0xFFE3BDB4);

  // Success (kid: ok)
  static const ok = Color(0xFF2E7D46);
  static const okFill = Color(0xFFE4F1E6);

  // Info
  static const info = Color(0xFF3E6E8E);
  static const infoFill = Color(0xFFE3ECF1);

  // Gold (on dark plan banner only)
  static const gold = Color(0xFFF2C14E);

  // Disabled state
  static const disabled = Color(0xFFEBEEE6);
  static const disabledText = Color(0xFFAEB6A9);

  // ─────────────────────────────────────────────────────────────────
  // Back-compat aliases. Existing screens/widgets still reference
  // these names; they now point at sage-forest values so the visual
  // migration happens automatically as screens are restyled. New
  // code should use the names above (forest, ink, sage, …).
  // ─────────────────────────────────────────────────────────────────
  static const primary = forest;                 // was #6C3FC5 purple
  static const primaryLight = sage;              // was #9B7FD4
  static const primaryDark = forestHover;        // was #4A2894
  static const accent = warnDot;                 // was #FF8C42 orange
  static const success = ok;                     // was #2ECC71
  static const warning = warn;                   // was #F39C12
  static const surface = paper;                  // was #F8F6FC
  static const cardLight = card;                 // was #FFFBFE
  static const textPrimary = ink;                // was #1A1A2E
  static const textSecondary = ink2;             // was #6B7280
  static const border = hair2;                   // was #E5E7EB
}

/// Type scale, matching the handoff's typography spec. Two families
/// (Bricolage Grotesque display, Hanken Grotesk body) + a mono eyebrow
/// role. All time values use tabular figures so digit widths don't
/// jitter while the timer ticks.
class AppText {
  // Display — Bricolage Grotesque 700, letter-spacing -0.02em
  static TextStyle screenTitle({Color? color}) => GoogleFonts.bricolageGrotesque(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4, // -0.02em @ 22px
        color: color ?? AppColors.ink,
      );

  static TextStyle bigTimer({Color? color, double size = 47}) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: size * -0.02,
        color: color ?? AppColors.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  // Alias for kid screens — they're built around AppText.title(size:)
  // and we want one canonical name across both modes.
  static TextStyle title({Color? color, double size = 22}) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: size * -0.02,
        color: color ?? AppColors.ink,
      );

  // Tabular-figures monospace-ish rendering for the 6-digit pairing
  // code entry field. Wide letter-spacing so each digit breathes.
  static TextStyle code({double size = 32}) => GoogleFonts.bricolageGrotesque(
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: size * 0.15,
        color: AppColors.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle statValue({Color? color}) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: color ?? AppColors.ink,
      );

  static TextStyle cardHeader({Color? color, double size = 15}) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: color ?? AppColors.ink,
      );

  // Body — Hanken Grotesk
  static TextStyle body({Color? color, double size = 13.5}) =>
      GoogleFonts.hankenGrotesk(
        fontSize: size,
        fontWeight: FontWeight.w500,
        color: color ?? AppColors.ink,
      );

  static TextStyle listTitle({Color? color}) =>
      GoogleFonts.hankenGrotesk(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.ink,
      );

  static TextStyle bodySecondary({Color? color, double size = 12}) =>
      GoogleFonts.hankenGrotesk(
        fontSize: size,
        fontWeight: FontWeight.w500,
        color: color ?? AppColors.ink2,
      );

  static TextStyle button({Color? color}) =>
      GoogleFonts.hankenGrotesk(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.card,
      );

  static TextStyle timerDigits({Color? color, double size = 18}) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  // Eyebrow — monospace, UPPERCASE, muted
  static TextStyle eyebrow({Color? color}) => GoogleFonts.jetBrainsMono(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.9, // ~0.08em
        color: color ?? AppColors.muted,
      ).copyWith(height: 1.0);
}

/// Shape tokens. Cards/buttons/inputs each have a single canonical
/// radius so visual consistency doesn't drift screen by screen.
class AppRadius {
  static const card = 12.0;       // Parent cards
  static const kidCard = 14.0;    // Kid cards
  static const button = 10.0;     // Buttons, inputs, segmented
  static const iconTile = 8.0;    // Icon tiles, small chips
  static const monogram = 11.0;   // Monogram avatar
  static const avatarKid = 16.0;  // Larger kid profile avatar
  static const deviceScreen = 28.0;
}

class AppSpacing {
  static const screenPadding = 18.0;
  static const blockGap = 13.0;
  static const cardPadding = 14.0;
  static const cardPaddingKid = 16.0;
  static const rowVerticalPad = 11.0;
}

class AppTheme {
  /// A gentle fade-up transition applied on every platform (incl.
  /// web, which otherwise snaps between routes with no animation).
  /// Replacing the default instant/slide cut is the single cheapest
  /// win against the app's old "wireframe" feel.
  static const PageTransitionsTheme _transitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
    },
  );

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.forest,
      primary: AppColors.forest,
      onPrimary: AppColors.card,
      secondary: AppColors.sage,
      surface: AppColors.paper,
      onSurface: AppColors.ink,
      error: AppColors.danger,
      brightness: Brightness.light,
    );

    final baseText = GoogleFonts.hankenGroteskTextTheme(
      ThemeData.light().textTheme,
    );

    return ThemeData(
      useMaterial3: true,
      pageTransitionsTheme: _transitions,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.paper,
      textTheme: baseText,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.paper,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppText.screenTitle(),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        // Soft, brand-tinted drop shadow (not Material's grey tonal
        // elevation) so cards lift off the page without looking like
        // a flat wireframe. surfaceTintColor is cleared so the card
        // keeps its true colour at elevation.
        elevation: 3,
        shadowColor: AppColors.forest.withValues(alpha: 0.10),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.hair2, width: 0.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.forest,
          foregroundColor: AppColors.card,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: AppText.button(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.forest,
          side: const BorderSide(color: Color(0xFFCBD3C2)),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: AppText.button(color: AppColors.forest),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.forest,
          textStyle: AppText.button(color: AppColors.forest),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: AppColors.hair2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: AppColors.hair2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: AppColors.forest, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        hintStyle: AppText.body(color: AppColors.faint),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: AppColors.card,
          selectedForegroundColor: AppColors.ink,
          backgroundColor: const Color(0xFFEAEEE3),
          side: BorderSide.none,
          textStyle: AppText.button(color: AppColors.ink),
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.ink, size: 20),
      dividerTheme: const DividerThemeData(
        color: AppColors.line,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static ThemeData get dark {
    // Dark theme uses green-tinted neutrals so the palette stays
    // coherent with light mode. Not shown in mocks; values chosen
    // to keep contrast and brand identity.
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.forest,
      primary: AppColors.sage,
      onPrimary: AppColors.ink,
      secondary: AppColors.grass,
      surface: const Color(0xFF12160F),
      onSurface: const Color(0xFFE4E8DC),
      error: AppColors.danger,
      brightness: Brightness.dark,
    );

    final baseText = GoogleFonts.hankenGroteskTextTheme(
      ThemeData.dark().textTheme,
    );

    return ThemeData(
      useMaterial3: true,
      pageTransitionsTheme: _transitions,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF12160F),
      textTheme: baseText,
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF12160F),
        foregroundColor: const Color(0xFFE4E8DC),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppText.screenTitle(color: const Color(0xFFE4E8DC)),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1B201A),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: Color(0xFF26302A), width: 0.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.sage,
          foregroundColor: AppColors.ink,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: AppText.button(color: AppColors.ink),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.sage,
          side: const BorderSide(color: Color(0xFF2E3A33)),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: AppText.button(color: AppColors.sage),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1B201A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: Color(0xFF26302A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: Color(0xFF26302A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: AppColors.sage, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        hintStyle: AppText.body(color: const Color(0xFF8A938C)),
      ),
      iconTheme: const IconThemeData(color: Color(0xFFE4E8DC), size: 20),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF26302A),
        thickness: 1,
        space: 1,
      ),
    );
  }
}