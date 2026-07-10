import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Generic value-bearing option for [AppSegmentedGroup].
class AppSegment<T> {
  final T value;
  final String label;
  const AppSegment({required this.value, required this.label});
}

/// Custom segmented control matching the handoff spec: track
/// #EAEEE3, 9px radius, 4px inner padding; selected segment is
/// white with a soft shadow and ink text. Animated on selection
/// (~150ms) so taps feel responsive.
///
/// We don't use Material's `SegmentedButton` because its theming
/// is awkward to match the design (segment backgrounds, the track
/// surface, the indicator shadow) and the redesign called out the
/// specific colors. Implementing this directly is ~80 lines and
/// gives full control.
class AppSegmentedGroup<T> extends StatelessWidget {
  final List<AppSegment<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  const AppSegmentedGroup({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEAEEE3),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: options.map((opt) {
          final isSelected = opt.value == selected;
          return Expanded(
            child: _SegmentButton(
              label: opt.label,
              selected: isSelected,
              onTap: () => onSelected(opt.value),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.card : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppText.button(
            color: selected ? AppColors.ink : AppColors.muted,
          ),
        ),
      ),
    );
  }
}