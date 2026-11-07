import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../constants/constants.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';

/// Severity / health level shared by alerts, DTC codes, readiness monitors
/// and request states. Colors come from the active theme: use [colorOf] /
/// [softOf].
enum StatusLevel {
  ok(Icons.check_circle_outline_rounded),
  info(Icons.info_outline_rounded),
  warning(Icons.warning_amber_rounded),
  critical(Icons.error_outline_rounded),

  /// No status meaning: "Demo", counts, labels.
  neutral(Icons.circle_outlined);

  const StatusLevel(this.icon);

  final IconData icon;

  /// Foreground (text / icon) color in the current theme.
  Color colorOf(BuildContext context) {
    final p = context.colors;
    return switch (this) {
      StatusLevel.ok => p.ok,
      StatusLevel.info => p.primary,
      StatusLevel.warning => p.warn,
      StatusLevel.critical => p.crit,
      StatusLevel.neutral => p.text2,
    };
  }

  /// Soft fill for pills, icon boxes and alert rows in the current theme.
  Color softOf(BuildContext context) {
    final p = context.colors;
    return switch (this) {
      StatusLevel.ok => p.okSoft,
      StatusLevel.info => p.primarySoft,
      StatusLevel.warning => p.warnSoft,
      StatusLevel.critical => p.critSoft,
      StatusLevel.neutral => p.surface2,
    };
  }
}

/// A compact soft pill, e.g. "Critical", "3 pending", "Connected".
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.level,
    this.showIcon = false,
    this.icon,
  });

  final String label;
  final StatusLevel level;

  /// Show the level's icon (or [icon]) before the label.
  final bool showIcon;

  /// Overrides the level's default icon (implies [showIcon]).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = level.colorOf(context);
    return Container(
      constraints: BoxConstraints(minHeight: 24.h),
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: level.softOf(context),
        borderRadius: BorderRadius.circular(AppSizes.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon || icon != null) ...[
            Icon(icon ?? level.icon, size: 14.r, color: fg),
            SizedBox(width: AppSizes.space4.w),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.label.copyWith(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
