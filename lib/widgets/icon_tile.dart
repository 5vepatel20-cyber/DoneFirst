import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Small rounded-square tile with a pale semantic fill + matching
/// line icon. Used across the redesign wherever the prototype
/// shows a colored icon in a chip-like container (info banners,
/// profile preview, status indicators, etc.). Tile sizes in the
/// spec range from 30–40px; pick whichever fits the parent layout.
///
/// Pass [Icon] widget directly, or use [color] to draw a flat-tint
/// tile without an icon (e.g. for monogram avatars in tile form).
class IconTile extends StatelessWidget {
  final IconData? icon;
  final double size;
  final Color background;
  final Color iconColor;
  final double radius;
  final double iconSize;

  /// OK / success tile (okFill bg, ok icon).
  const IconTile.ok({
    super.key,
    this.icon,
    this.size = 36,
    this.iconSize = 18,
  })  : background = AppColors.okFill,
        iconColor = AppColors.ok,
        radius = AppRadius.iconTile;

  /// Info tile (infoFill bg, info icon).
  const IconTile.info({
    super.key,
    this.icon,
    this.size = 36,
    this.iconSize = 18,
  })  : background = AppColors.infoFill,
        iconColor = AppColors.info,
        radius = AppRadius.iconTile;

  /// Warning tile (warnFill bg, warn icon).
  const IconTile.warn({
    super.key,
    this.icon,
    this.size = 36,
    this.iconSize = 18,
  })  : background = AppColors.warnFill,
        iconColor = AppColors.warn,
        radius = AppRadius.iconTile;

  /// Danger tile (dangerFill bg, danger icon).
  const IconTile.danger({
    super.key,
    this.icon,
    this.size = 36,
    this.iconSize = 18,
  })  : background = AppColors.dangerFill,
        iconColor = AppColors.danger,
        radius = AppRadius.iconTile;

  /// Sage tile (sageFill bg, forest icon). Generic neutral chip.
  const IconTile.sage({
    super.key,
    this.icon,
    this.size = 36,
    this.iconSize = 18,
  })  : background = AppColors.sageFill,
        iconColor = AppColors.forest,
        radius = AppRadius.iconTile;

  const IconTile({
    super.key,
    this.icon,
    required this.background,
    required this.iconColor,
    this.size = 36,
    this.iconSize = 18,
    this.radius = AppRadius.iconTile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: icon == null
          ? const SizedBox.shrink()
          : Icon(icon, size: iconSize, color: iconColor),
    );
  }
}