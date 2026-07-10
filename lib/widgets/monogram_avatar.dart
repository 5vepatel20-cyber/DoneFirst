import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Rounded-square tinted initial avatar. Two canonical variants:
/// parent (sageSoft bg, forest letter) and kid (grass bg, white
/// letter). Used in the dashboard per-child rows and on the kid
/// profile screen. The fallback when [name] is empty is a generic
/// user-glyph so the avatar is never blank.
class MonogramAvatar extends StatelessWidget {
  final String name;
  final double size;

  /// Parent variant: sageSoft background, forest initial, 46px.
  const MonogramAvatar.parent({
    super.key,
    required this.name,
    this.size = 46,
  }) : isKid = false;

  /// Kid profile variant: grass background, white initial, 86px.
  const MonogramAvatar.kid({
    super.key,
    required this.name,
    this.size = 86,
  }) : isKid = true;

  /// Raw constructor for callers that want non-standard sizing.
  const MonogramAvatar({
    super.key,
    required this.name,
    required this.size,
    required this.isKid,
  });

  final bool isKid;

  String get _initial {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    // First non-whitespace char, uppercased. Handles emojis poorly
    // but the kid-name convention is letters only.
    return trimmed[0].toUpperCase();
  }

  Color get _bg => isKid ? AppColors.grass : AppColors.sageSoft;

  Color get _letterColor => isKid ? Colors.white : AppColors.forest;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(
      isKid && size >= 80 ? AppRadius.avatarKid : AppRadius.monogram,
    );

    // Letter scales with size so 46px and 86px variants both feel
    // balanced — we don't reuse a fixed fontSize because the
    // containers differ by ~2x.
    final fontSize = size * 0.42;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: radius,
      ),
      alignment: Alignment.center,
      child: Text(
        _initial,
        style: GoogleFonts.bricolageGrotesque(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: _letterColor,
          height: 1.0,
        ),
      ),
    );
  }
}