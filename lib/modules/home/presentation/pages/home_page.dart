import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/core.dart';
import '../../../../core/localization/app_localizations.dart';
import '../widgets/counter_card.dart';
import '../widgets/welcome_header.dart';

/// Tappable card that opens roadside assistance.
class _RoadsideBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return AppCard(
      onTap: () => Navigator.of(context).pushNamed(AppRoutes.roadside),
      child: Row(
        children: [
          const IconBox(Icons.car_repair_rounded, size: 48),
          SizedBox(width: AppSizes.space12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('roadside_assistance'),
                  style: AppTextStyles.title.copyWith(color: p.text),
                ),
                SizedBox(height: AppSizes.space4.h),
                Text(
                  context.tr('roadside_banner_sub'),
                  style: AppTextStyles.label.copyWith(
                    fontWeight: FontWeight.w400,
                    color: p.text2,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: AppSizes.space8.w),
          Icon(Icons.chevron_right_rounded, color: p.muted, size: 22.r),
        ],
      ),
    );
  }
}

/// Legacy template home page: welcome header, counter card and a roadside
/// shortcut. The signed-in app's real home is the Home tab of AppShell.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(title: context.tr('home')),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsetsDirectional.fromSTEB(
                  AppSizes.space20.w,
                  AppSizes.space8.h,
                  AppSizes.space20.w,
                  AppSizes.space24.h,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const WelcomeHeader(),
                    SizedBox(height: AppSizes.space24.h),
                    const CounterCard(),
                    SizedBox(height: AppSizes.space16.h),
                    _RoadsideBanner(),
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
