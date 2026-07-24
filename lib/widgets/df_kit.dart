import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// DoneFirst premium component kit. The shared building blocks every
/// rebuilt screen composes from, matching the Brand-sheet components:
/// chunky-shadow buttons, warm cards, chips, segmented control, section
/// labels, avatars, status pills, and stat tiles.
///
/// Import this (plus `app_theme.dart`) and prefer these over raw
/// Material widgets so the premium look stays consistent screen to
/// screen.

enum DfButtonVariant { primary, ink, amber, outline, danger, ghost }

/// Signature button — flat fill with the hard `0 4px 0 <darker>` bottom
/// edge that presses down on tap (the edge collapses and the button
/// nudges down 4px). Height ≈52, weight 800.
class DfButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final DfButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool expand;

  const DfButton(
    this.label, {
    super.key,
    this.onPressed,
    this.variant = DfButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  const DfButton.ink(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
  }) : variant = DfButtonVariant.ink;

  const DfButton.amber(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
  }) : variant = DfButtonVariant.amber;

  const DfButton.outline(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
  }) : variant = DfButtonVariant.outline;

  const DfButton.danger(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
  }) : variant = DfButtonVariant.danger;

  @override
  State<DfButton> createState() => _DfButtonState();
}

class _DfButtonState extends State<DfButton> {
  bool _down = false;

  ({Color fill, Color edge, Color fg, Color? border}) get _palette {
    switch (widget.variant) {
      case DfButtonVariant.primary:
        return (
          fill: AppColors.green,
          edge: AppColors.greenDeep,
          fg: Colors.white,
          border: null,
        );
      case DfButtonVariant.ink:
        return (
          fill: AppColors.ink,
          edge: const Color(0xFF0E0C09),
          fg: Colors.white,
          border: null,
        );
      case DfButtonVariant.amber:
        return (
          fill: AppColors.amber,
          edge: const Color(0xFFB96F1C),
          fg: Colors.white,
          border: null,
        );
      case DfButtonVariant.danger:
        return (
          fill: AppColors.dangerBg,
          edge: const Color(0xFFE9C6BF),
          fg: AppColors.dangerFg,
          border: null,
        );
      case DfButtonVariant.outline:
        return (
          fill: AppColors.card,
          edge: AppColors.borderCol,
          fg: AppColors.ink,
          border: AppColors.borderCol,
        );
      case DfButtonVariant.ghost:
        return (
          fill: Colors.transparent,
          edge: Colors.transparent,
          fg: AppColors.ink,
          border: null,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _palette;
    final enabled = widget.onPressed != null && !widget.loading;
    final pressed = _down && enabled;

    final child = widget.loading
        ? SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: p.fg),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 19, color: p.fg),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.button(color: p.fg),
                ),
              ),
            ],
          );

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          width: widget.expand ? double.infinity : null,
          height: 52,
          transform: Matrix4.translationValues(0, pressed ? 4 : 0, 0),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: p.fill,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: p.border != null
                ? Border.all(color: p.border!, width: 1.5)
                : null,
            boxShadow: (widget.variant == DfButtonVariant.ghost || pressed)
                ? null
                : [
                    BoxShadow(
                      color: p.edge,
                      offset: const Offset(0, 4),
                      blurRadius: 0,
                    ),
                  ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Warm card — white surface, 1px warm border, r22, soft brown shadow.
class DfCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  const DfCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      decoration: BoxDecoration(
        color: color ?? AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: borderColor ?? AppColors.borderCol, width: 1),
        boxShadow: AppShadows.card,
      ),
      // A transparent Material ancestor so ListTile/ExpansionTile/InkWell
      // children paint their background + ink splashes correctly instead
      // of asserting against the colored box above.
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      ),
    );
    if (onTap == null) return content;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
  }
}

/// UPPERCASE tracked mono label that introduces a section.
class DfSectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const DfSectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Row(
        children: [
          Expanded(child: Text(text.toUpperCase(), style: AppText.label())),
          ?trailing,
        ],
      ),
    );
  }
}

enum DfPillTone { success, attention, danger, info, neutral }

/// Small status pill (Online / Approved / Pending / Checking…).
class DfStatusPill extends StatelessWidget {
  final String label;
  final DfPillTone tone;
  final IconData? icon;
  final bool dot;
  const DfStatusPill(
    this.label, {
    super.key,
    this.tone = DfPillTone.neutral,
    this.icon,
    this.dot = false,
  });

  ({Color fg, Color bg}) get _c {
    switch (tone) {
      case DfPillTone.success:
        return (fg: AppColors.successFg, bg: AppColors.successBg);
      case DfPillTone.attention:
        return (fg: AppColors.amberDeep, bg: AppColors.attentionBg);
      case DfPillTone.danger:
        return (fg: AppColors.dangerFg, bg: AppColors.dangerBg);
      case DfPillTone.info:
        return (fg: AppColors.infoFg, bg: AppColors.infoBg);
      case DfPillTone.neutral:
        return (fg: AppColors.ink70, bg: AppColors.border2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: c.fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          if (icon case final ic?) ...[
            Icon(ic, size: 13, color: c.fg),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: AppText.caption(
              color: c.fg,
            ).copyWith(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Rounded monogram / avatar tile carrying an initial (or emoji).
class DfAvatar extends StatelessWidget {
  final String label; // single char or emoji
  final double size;
  final Color? color;
  final bool circle;
  const DfAvatar(
    this.label, {
    super.key,
    this.size = 44,
    this.color,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    final base = color ?? AppColors.green;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.14),
        borderRadius: circle ? null : BorderRadius.circular(size * 0.30),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
      ),
      alignment: Alignment.center,
      child: Text(
        label.characters.isEmpty ? '?' : label.characters.first.toUpperCase(),
        style: AppText.cardHeader(color: base, size: size * 0.40),
      ),
    );
  }
}

/// A single stat tile — big Bricolage numeral over a muted caption.
class DfStatTile extends StatelessWidget {
  final String value;
  final String caption;
  final Color? valueColor;
  final CrossAxisAlignment align;
  const DfStatTile(
    this.value,
    this.caption, {
    super.key,
    this.valueColor,
    this.align = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      children: [
        Text(
          value,
          style: AppText.statValue(
            color: valueColor ?? AppColors.ink,
            size: 24,
          ),
        ),
        const SizedBox(height: 3),
        Text(caption, style: AppText.caption()),
      ],
    );
  }
}

/// Rounded chip — used for tags, packs, day selectors. Filled when
/// [selected].
class DfChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  const DfChip(
    this.label, {
    super.key,
    this.selected = false,
    this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.green : AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(
            color: selected ? AppColors.green : AppColors.borderCol,
            width: 1.4,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.white : AppColors.ink70,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppText.body(
                size: 14,
                w: FontWeight.w700,
                color: selected ? Colors.white : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Segmented control — `#F1EADB` track, a white selected thumb with a
/// soft shadow. Generic over the option value [T].
class DfSegmented<T> extends StatelessWidget {
  final List<({T value, String label})> options;
  final T selected;
  final ValueChanged<T> onChanged;
  const DfSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.border2,
        borderRadius: BorderRadius.circular(AppRadius.segment),
      ),
      child: Row(
        children: options.map((o) {
          final isSel = o.value == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(o.value),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSel ? AppColors.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  boxShadow: isSel
                      ? const [
                          BoxShadow(
                            color: Color(0x1A241209),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  o.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(
                    size: 14,
                    w: FontWeight.w700,
                    color: isSel ? AppColors.ink : AppColors.ink70,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Friendly empty-state block — icon tile, title, one-line hint, and an
/// optional primary CTA. Never a blank scaffold.
class DfEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final String? ctaLabel;
  final VoidCallback? onCta;
  const DfEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    this.ctaLabel,
    this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: AppColors.greenTint,
                borderRadius: BorderRadius.circular(AppRadius.tile),
              ),
              child: Icon(icon, color: AppColors.green, size: 30),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.cardHeader(size: 19),
            ),
            const SizedBox(height: 8),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: AppText.body(size: 14),
            ),
            if (ctaLabel != null && onCta != null) ...[
              const SizedBox(height: 22),
              DfButton(ctaLabel!, onPressed: onCta, expand: false),
            ],
          ],
        ),
      ),
    );
  }
}
