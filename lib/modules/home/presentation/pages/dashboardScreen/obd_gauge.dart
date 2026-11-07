import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/core.dart';

/// One live OBD reading on the Home "Live data" grid: icon + label on top,
/// the value (tabular figures) with its unit below.
///
/// Looks like a [StatTile], but the value and the unit are separate [Text]s so
/// the number can be found and read on its own. When the reading crosses
/// [dangerAt] (or drops below [dangerBelow]) the tile switches to the
/// critical status color; a missing reading shows a muted "--".
class OBDGauge extends StatelessWidget {
  const OBDGauge({
    super.key,
    required this.value,
    required this.label,
    required this.unit,
    required this.icon,
    this.dangerAt,
    this.dangerBelow,
    this.decimals = 0,
  });

  final double? value;
  final String label;
  final String unit;
  final IconData icon;

  /// Value at or above which the reading is critical (e.g. coolant ≥ 105 °C).
  final double? dangerAt;

  /// Value below which the reading is critical (e.g. battery < 11.5 V).
  final double? dangerBelow;

  final int decimals;

  bool get _inDanger {
    final v = value;
    if (v == null) return false;
    return (dangerAt != null && v >= dangerAt!) ||
        (dangerBelow != null && v < dangerBelow!);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final danger = _inDanger;
    final v = value;
    final valueColor = danger ? p.crit : (v == null ? p.muted : p.text);

    return AppCard(
      accent: danger ? p.crit : null,
      padding: EdgeInsets.all(AppSizes.space12.r),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconBox(icon, size: 28, color: danger ? p.crit : null),
                SizedBox(width: AppSizes.space8.w),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.label.copyWith(
                      fontWeight: FontWeight.w400,
                      color: p.text2,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: AppSizes.space12.h),
            // Scales down rather than overflowing on narrow phones.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              // Measurements read left-to-right ("64 km/h") in Arabic too.
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      v != null ? v.toStringAsFixed(decimals) : '--',
                      maxLines: 1,
                      style: AppTextStyles.headline.copyWith(color: valueColor),
                    ),
                    if (v != null) ...[
                      SizedBox(width: AppSizes.space4.w),
                      Text(
                        unit,
                        maxLines: 1,
                        style: AppTextStyles.label.copyWith(color: p.text2),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
