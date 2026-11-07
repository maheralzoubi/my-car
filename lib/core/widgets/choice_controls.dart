import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../constants/constants.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';

/// A pill filter: "All 3", "Critical 1". Selected = inverted (text color
/// fill). Put several in a horizontally scrolling row.
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Optional count shown after the label.
  final int? count;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final fg = selected ? p.bg : p.text2;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? p.text : p.surface,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? p.text : p.borderStrong),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          // Sized to its content: an aligned Container would stretch to the
          // full width inside a Wrap.
          child: SizedBox(
            height: 36.h,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14.w),
              child: Center(
                widthFactor: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16.r, color: fg),
                      SizedBox(width: 6.w),
                    ],
                    Text(label, style: AppTextStyles.label.copyWith(color: fg)),
                    if (count != null) ...[
                      SizedBox(width: 6.w),
                      Text(
                        '$count',
                        style: AppTextStyles.numeric(
                          AppTextStyles.label,
                        ).copyWith(color: fg.withValues(alpha: 0.75)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// iOS-style segmented control, e.g. Light / Dark / System or Metric /
/// Imperial. Equal-width segments on a neutral track.
class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  /// (value, label) pairs, in display order.
  final List<(T, String)> segments;
  final T value;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return Container(
      padding: EdgeInsets.all(3.r),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd.r),
      ),
      child: Row(
        children: [
          for (final (v, label) in segments)
            Expanded(
              child: Semantics(
                button: true,
                selected: v == value,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onChanged == null ? null : () => onChanged!(v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 36.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: v == value ? p.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(9.r),
                      boxShadow: v == value
                          ? const [
                              BoxShadow(
                                color: Color(0x1F101828),
                                blurRadius: 2,
                                offset: Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.label.copyWith(
                        color: v == value ? p.text : p.text2,
                        fontWeight: v == value
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
