import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../constants/constants.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';

/// Centered placeholder for empty lists, errors and "not connected" states:
/// an icon in a soft circle, a title, an optional message and action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.iconColor,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;

  /// Icon tone, e.g. the ok color for "No codes found". Defaults to neutral.
  final Color? iconColor;

  /// Optional button below the message, e.g. "Retry" or "Connect".
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tone = iconColor ?? p.text2;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSizes.space32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72.r,
              height: 72.r,
              decoration: BoxDecoration(
                color: iconColor == null
                    ? p.surface2
                    : tone.withValues(alpha: dark ? 0.16 : 0.1),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 34.r, color: tone),
            ),
            SizedBox(height: AppSizes.space16.h),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.title.copyWith(color: p.text),
            ),
            if (message != null) ...[
              SizedBox(height: AppSizes.space8.h),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(color: p.text2),
              ),
            ],
            if (action != null) ...[
              SizedBox(height: AppSizes.space24.h),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
