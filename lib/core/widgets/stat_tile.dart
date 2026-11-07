import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../constants/constants.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';
import 'app_card.dart';

/// A small card showing one metric: icon + label on top, big value below.
///
/// The value shrinks to fit rather than overflowing, so tiles are safe in
/// tight grids and with long Arabic labels. Numbers use tabular figures.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.unit,
    this.valueColor,
    this.accent,
    this.onTap,
  });

  final String label;
  final String value;

  /// Typically a small [IconBox] (size 28).
  final Widget? icon;

  /// Shown after the value in a smaller style, e.g. "km/h".
  final String? unit;

  /// Defaults to the primary text color. Use a status color only for status.
  final Color? valueColor;

  /// Tints the card, e.g. a status color.
  final Color? accent;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return AppCard(
      accent: accent,
      onTap: onTap,
      padding: EdgeInsets.all(AppSizes.space12.r),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  icon!,
                  SizedBox(width: AppSizes.space8.w),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.label.copyWith(
                      fontWeight: FontWeight.w400,
                      color: p.text2,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: AppSizes.space8.h),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text.rich(
                TextSpan(
                  text: value,
                  style: AppTextStyles.headline.copyWith(
                    color: valueColor ?? p.text,
                  ),
                  children: [
                    if (unit != null)
                      TextSpan(
                        text: ' $unit',
                        style: AppTextStyles.label.copyWith(color: p.text2),
                      ),
                  ],
                ),
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
