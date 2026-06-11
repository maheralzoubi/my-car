import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/constants/constants.dart';
import '../widgets/counter_card.dart';
import '../widgets/welcome_header.dart';

class _RoadsideBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pushNamed(AppRoutes.roadside),
      child: Container(
        padding: EdgeInsets.all(16.r),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A0A00), Color(0xFF2D1500)],
          ),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: AppColors.accentOrange.withValues(alpha: 0.4),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentOrange.withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56.r,
              height: 56.r,
              decoration: BoxDecoration(
                color: AppColors.accentOrange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(
                    color: AppColors.accentOrange.withValues(alpha: 0.4)),
              ),
              child: Icon(Icons.car_repair,
                  color: AppColors.accentOrange, size: 28.r),
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Roadside Assistance',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 3.h),
                  Text(
                    'Towing, battery, tire, fuel & more\nAvg. response in 15 minutes',
                    style: TextStyle(
                      color: AppColors.textLight.withValues(alpha: 0.6),
                      fontSize: 11.sp,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                color: AppColors.accentOrange, size: 16.r),
          ],
        ),
      ),
    );
  }
}

/// Home screen: welcome header and counter card.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.homeTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            top: AppSizes.space8.h,
            left: AppSizes.space16.w,
            right: AppSizes.space16.w,
            bottom: AppSizes.space24.h,
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
    );
  }
}
