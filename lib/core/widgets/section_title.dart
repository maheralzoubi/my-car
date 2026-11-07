import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../constants/constants.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';

/// Section heading (17 / semibold) with an optional trailing widget, usually
/// a [SectionLink] such as "See graph ›".
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSizes.space12.h),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.title.copyWith(color: context.colors.text),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// "See all ›" style link for [SectionTitle.trailing]. The chevron mirrors in
/// RTL.
class SectionLink extends StatelessWidget {
  const SectionLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radiusSm.r),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 36.h),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSizes.space4.w),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTextStyles.label.copyWith(
                  fontSize: 14.sp,
                  color: p.primary,
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18.r, color: p.primary),
            ],
          ),
        ),
      ),
    );
  }
}
