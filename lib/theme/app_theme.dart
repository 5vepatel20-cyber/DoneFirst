import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Premium "warm" design tokens — the approved DoneFirst direction (1a).
///
/// Cream paper (#F7F2E8), emerald (#23A15C), amber (#E38B2B). This
/// REPLACES the earlier cool "sage-forest" values. Every legacy token
/// name (forest, sage, primary, success, …) is preserved as an alias
/// that now points at the warm hex, so the ~200 existing references in
/// screens/widgets reskin automatically without a mass rename. New and
/// rebuilt screens should prefer the canonical names in the first block
/// (green, amber, ink, paper, border, …).
class AppColors {
  // ── Brand & surface ────────────────────────────────────────────────
  static const green = Color(0xFF23A15C); // primary: go, approved, focus
  static const greenDeep = Color(0xFF1C824B); // button shadow, pressed
  static const greenBright = Color(0xFF35B06E); // highlights, dark accents
  static const greenTint = Color(0xFFE6F3EA); // success surface / fills
  static const amber = Color(0xFFE38B2B); // timer, attention, upgrade
  static const amberDeep = Color(0xFFA9670F); // amber text on tint
  static const amberTint = Color(0xFFFBEEDA); // attention surface
  static const amberTint2 = Color(0xFFF5D9A6);

  static const ink = Color(0xFF24201A); // primary text, dark surfaces
  static const ink70 = Color(0xFF5F5648); // body text
  static const inkSecondary = Color(0xFF6B6252);
  static const ink45 = Color(0xFF9A9082); // muted text / captions
  static const inkMuted2 = Color(0xFF857B6E);
  static const inkFaint = Color(0xFFB3AA9B); // disabled text, faint icons
  static const inkFaint2 = Color(0xFFC4BAA9);

  static const paper = Color(0xFFF7F2E8); // app scaffold background
  static const canvas = Color(0xFFE7DFCF); // behind cards (rare)
  static const card = Color(0xFFFFFFFF);
  static const borderCol = Color(0xFFEBE3D4); // hairlines, card edges
  static const border2 = Color(0xFFF1EADB); // internal dividers
  static const borderDashed = Color(0xFFD4C9B5);

  // Warm shadow used under cards (0 10px 24px -18px rgba(60,40,10,0.5)).
  static const shadow = Color(0xFF3C280A);

  // ── Semantic ───────────────────────────────────────────────────────
  // successFg is the deeper emerald (not the bright brand green) so that
  // small success icons/labels clear WCAG 3:1 for graphics on greenTint
  // (the bright #23A15C is only 2.9:1 there). Buttons still use `green`.
  static const successFg = greenDeep;
  static const successBg = greenTint;
  static const attentionFg = amber;
  static const attentionBg = amberTint;
  static const dangerFg = Color(0xFFC0574A);
  static const dangerBg = Color(0xFFF6E3E0);
  static const infoFg = Color(0xFF3E7CA8);
  static const infoBg = Color(0xFFE4EDF3);

  // Kid celebratory gradient stops.
  static const kidGradTop = Color(0xFF35B06E);
  static const kidGradBottom = Color(0xFF1F8F55);

  // ── Legacy aliases (values remapped to the warm palette) ────────────
  // Kept so existing screens compile & reskin. Prefer the names above.
  static const ink2 = ink70; // secondary text
  static const muted = ink45; // tertiary text
  static const faint = inkFaint; // placeholder text
  static const hair = borderCol; // device/section hairlines
  static const hair2 = borderCol; // card & input borders
  static const line = border2; // internal dividers

  static const forest = green; // primary buttons, brand
  static const forestHover = greenDeep; // pressed/hover
  static const deep = greenDeep; // banner / timer card bg

  static const sage = greenBright; // accent
  static const sageFill = greenTint; // chips, info banners
  static const sageSoft = greenTint; // parent monogram bg

  static const grass = green; // kid primary
  static const grassDeep = greenDeep; // kid locked screen bg
  static const kidBg = paper; // kid scaffold background
  static const kidLine = borderCol;
  static const kidInk = ink;

  static const warn = amberDeep; // warning text
  static const warnDot = amber; // streak flame, timer dot
  static const warnFill = amberTint;
  static const warnBd = amberTint2;

  static const danger = dangerFg;
  static const dangerFill = dangerBg;
  static const dangerBd = Color(0xFFE9C6BF);

  static const ok =
      greenDeep; // success fg — 3:1-safe on okFill (see successFg)
  static const okFill = greenTint;

  static const info = infoFg;
  static const infoFill = infoBg;

  static const gold = Color(0xFFE8B84B); // plan banner accent on dark

  static const disabled = Color(0xFFEFE8DA);
  static const disabledText = inkFaint;

  // Material-name aliases used in a few older widgets.
  static const primary = green;
  static const primaryLight = greenBright;
  static const primaryDark = greenDeep;
  static const accent = amber;
  static const success = green;
  static const warning = amberDeep;
  static const surface = paper;
  static const cardLight = card;
  static const textPrimary = ink;
  static const textSecondary = ink70;
  static const border = borderCol;
}

/// Type scale from the handoff. Display = Bricolage Grotesque (700/800,
/// negative tracking), body/UI = Hanken Grotesk, mono eyebrow = JetBrains
/// Mono. Time/stat numerals use tabular figures so digits don't jitter.
class AppText {
  // ── Display (Bricolage Grotesque) ──────────────────────────────────
  static TextStyle display({
    Color? color,
    double size = 40,
    FontWeight w = FontWeight.w800,
  }) => GoogleFonts.bricolageGrotesque(
    fontSize: size,
    fontWeight: w,
    letterSpacing: size * -0.02,
    height: 1.02,
    color: color ?? AppColors.ink,
  );

  static TextStyle screenTitle({Color? color, double size = 24}) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: size * -0.02,
        color: color ?? AppColors.ink,
      );

  static TextStyle title({Color? color, double size = 22}) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: size * -0.02,
        color: color ?? AppColors.ink,
      );

  static TextStyle bigTimer({Color? color, double size = 54}) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: size * -0.02,
        height: 1.0,
        color: color ?? AppColors.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle statValue({Color? color, double size = 22}) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        color: color ?? AppColors.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle cardHeader({Color? color, double size = 17}) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: color ?? AppColors.ink,
      );

  static TextStyle timerDigits({Color? color, double size = 18}) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  // ── Body / UI (Hanken Grotesk) ─────────────────────────────────────
  static TextStyle body({
    Color? color,
    double size = 15,
    FontWeight w = FontWeight.w500,
  }) => GoogleFonts.hankenGrotesk(
    fontSize: size,
    fontWeight: w,
    height: 1.45,
    color: color ?? AppColors.ink70,
  );

  static TextStyle listTitle({Color? color, double size = 15}) =>
      GoogleFonts.hankenGrotesk(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.ink,
      );

  static TextStyle bodySecondary({Color? color, double size = 13}) =>
      GoogleFonts.hankenGrotesk(
        fontSize: size,
        fontWeight: FontWeight.w500,
        height: 1.4,
        color: color ?? AppColors.ink70,
      );

  static TextStyle button({Color? color, double size = 15}) =>
      GoogleFonts.hankenGrotesk(
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.1,
        color: color ?? AppColors.card,
      );

  // ── Label / eyebrow (JetBrains Mono, UPPERCASE, tracked, muted) ────
  static TextStyle label({Color? color, double size = 13}) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: color ?? AppColors.ink45,
        height: 1.0,
      );

  static TextStyle eyebrow({Color? color}) => label(color: color, size: 11);

  static TextStyle code({double size = 32, Color? color}) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: size * 0.12,
        color: color ?? AppColors.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle caption({Color? color, double size = 12}) =>
      GoogleFonts.hankenGrotesk(
        fontSize: size,
        fontWeight: FontWeight.w500,
        color: color ?? AppColors.ink45,
      );
}

/// Radius tokens (mock: pill 999 · card 22 · tile 18 · chip/segment 14 ·
/// small 10–12 · button 13–18).
class AppRadius {
  static const pill = 999.0;
  static const card = 22.0; // parent + kid cards
  static const kidCard = 22.0;
  static const tile = 18.0;
  static const chip = 14.0;
  static const segment = 14.0;
  static const button = 16.0;
  static const iconTile = 14.0;
  static const small = 12.0;
  static const monogram = 14.0;
  static const avatarKid = 18.0;
  static const deviceScreen = 28.0;
}

class AppSpacing {
  static const screenPadding = 20.0;
  static const blockGap = 14.0;
  static const cardPadding = 16.0;
  static const cardPaddingKid = 18.0;
  static const rowVerticalPad = 12.0;
}

/// Signature elevations. The card shadow is warm and soft; the button
/// shadow is the chunky hard `0 4px 0` bottom edge (see [DfButton]).
class AppShadows {
  static const card = [
    BoxShadow(
      color: Color(0x33241209), // ~rgba(60,40,10,0.20) softened
      blurRadius: 24,
      spreadRadius: -14,
      offset: Offset(0, 10),
    ),
  ];

  static const raised = [
    BoxShadow(
      color: Color(0x22241209),
      blurRadius: 14,
      spreadRadius: -8,
      offset: Offset(0, 6),
    ),
  ];
}

class AppTheme {
  /// Gentle fade-up between routes on every platform (web included,
  /// which otherwise snaps with no animation).
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
      seedColor: AppColors.green,
      primary: AppColors.green,
      onPrimary: AppColors.card,
      secondary: AppColors.amber,
      surface: AppColors.paper,
      onSurface: AppColors.ink,
      error: AppColors.dangerFg,
      brightness: Brightness.light,
    );

    final baseText = GoogleFonts.hankenGroteskTextTheme(
      ThemeData.light().textTheme,
    ).apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);

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
        elevation: 6,
        shadowColor: AppColors.shadow.withValues(alpha: 0.16),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.borderCol, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: AppColors.card,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: AppText.button(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.borderCol, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: AppText.button(color: AppColors.ink),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.green,
          textStyle: AppText.button(color: AppColors.green, size: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: AppColors.borderCol),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: AppColors.borderCol),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: AppColors.green, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        hintStyle: AppText.body(color: AppColors.inkFaint),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: AppColors.card,
          selectedForegroundColor: AppColors.ink,
          backgroundColor: AppColors.border2,
          foregroundColor: AppColors.ink70,
          side: BorderSide.none,
          textStyle: AppText.button(color: AppColors.ink, size: 14),
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.ink, size: 22),
      dividerTheme: const DividerThemeData(
        color: AppColors.border2,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static ThemeData get dark {
    // Warm-neutral dark variant (not drawn in the mocks) that keeps the
    // emerald/amber identity. Surfaces are deep warm browns, not greys.
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.green,
      primary: AppColors.greenBright,
      onPrimary: AppColors.ink,
      secondary: AppColors.amber,
      surface: const Color(0xFF1A1712),
      onSurface: const Color(0xFFEDE6D9),
      error: AppColors.dangerFg,
      brightness: Brightness.dark,
    );

    final baseText =
        GoogleFonts.hankenGroteskTextTheme(ThemeData.dark().textTheme).apply(
          bodyColor: const Color(0xFFEDE6D9),
          displayColor: const Color(0xFFEDE6D9),
        );

    return ThemeData(
      useMaterial3: true,
      pageTransitionsTheme: _transitions,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF14110D),
      textTheme: baseText,
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF14110D),
        foregroundColor: const Color(0xFFEDE6D9),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppText.screenTitle(color: const Color(0xFFEDE6D9)),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF211C16),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: Color(0xFF322B22), width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.greenBright,
          foregroundColor: AppColors.ink,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: AppText.button(color: AppColors.ink),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFEDE6D9),
          side: const BorderSide(color: Color(0xFF3A3227), width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: AppText.button(color: const Color(0xFFEDE6D9)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF211C16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: Color(0xFF322B22)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(color: Color(0xFF322B22)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
          borderSide: const BorderSide(
            color: AppColors.greenBright,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        hintStyle: AppText.body(color: const Color(0xFF8F857A)),
      ),
      iconTheme: const IconThemeData(color: Color(0xFFEDE6D9), size: 22),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF322B22),
        thickness: 1,
        space: 1,
      ),
    );
  }
}
