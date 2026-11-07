import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/core.dart';
import '../../../../core/localization/app_localizations.dart';

/// Header section for the home screen with title and subtitle.
class WelcomeHeader extends StatelessWidget {
  const WelcomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('home_welcome'),
          style: AppTextStyles.headline.copyWith(color: p.text),
        ),
        SizedBox(height: AppSizes.space4.h),
        Text(
          context.tr('home_subtitle'),
          style: AppTextStyles.body.copyWith(color: p.text2),
        ),
      ],
    );
  }
}
