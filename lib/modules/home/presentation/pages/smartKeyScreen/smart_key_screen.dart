import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/localization/app_localizations.dart';

class SmartKeyScreen extends StatefulWidget {
  const SmartKeyScreen({super.key});

  @override
  State<SmartKeyScreen> createState() => _SmartKeyScreenState();
}

class _SmartKeyScreenState extends State<SmartKeyScreen>
    with SingleTickerProviderStateMixin {
  bool isLocked = true;
  bool engineRunning = false;
  late AnimationController _pulseController;

  static const Color _successGreen = Color(0xFF00E676);
  static const Color _successGreenDark = Color(0xFF00C853);
  static const Color _orangeDark = Color(0xFFFF5722);
  static const Color _blueDark = Color(0xFF0066FF);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.backgroundDark,
              AppColors.backgroundDarkBlue,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20.r),
                  child: Column(
                    children: [
                      _buildCarImage(),
                      SizedBox(height: 40.h),
                      _buildLockButton(),
                      SizedBox(height: 20.h),
                      _buildUnlockButton(),
                      SizedBox(height: 20.h),
                      _buildEngineButton(),
                      SizedBox(height: 40.h),
                      _buildQuickActions(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.all(20.r),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: AppColors.accentCyan),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            context.tr('smart_key_title'),
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
          const Spacer(),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: _successGreen.withValues(alpha: 0.1),
              border: Border.all(color: _successGreen),
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8.w,
                  height: 8.h,
                  decoration: const BoxDecoration(
                    color: _successGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 6.w),
                Text(
                  context.tr('connected'),
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: _successGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarImage() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: 300.w,
          height: 200.h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30.r),
            boxShadow: [
              BoxShadow(
                color: (isLocked ? AppColors.accentOrange : _successGreen)
                    .withValues(alpha: 0.3 + (_pulseController.value * 0.2)),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30.r),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    Icons.directions_car,
                    size: 120.r,
                    color: AppColors.accentCyan.withValues(alpha: 0.5),
                  ),
                ),
                if (isLocked)
                  Center(
                    child: Icon(
                      Icons.lock,
                      size: 60.r,
                      color: AppColors.accentOrange,
                    ),
                  ),
                if (engineRunning)
                  Positioned(
                    top: 20,
                    right: 20,
                    child: Container(
                      padding: EdgeInsets.all(10.r),
                      decoration: BoxDecoration(
                        color: _successGreen.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _successGreen,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.power_settings_new,
                        color: _successGreen,
                        size: 24.r,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLockButton() {
    return GestureDetector(
      onTap: () {
        setState(() {
          isLocked = true;
          engineRunning = false;
        });
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(25.r),
        decoration: BoxDecoration(
          gradient: isLocked
              ? const LinearGradient(
                  colors: [AppColors.accentOrange, _orangeDark],
                )
              : null,
          color: isLocked ? null : AppColors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: isLocked
                ? AppColors.transparent
                : AppColors.accentCyan.withValues(alpha: 0.2),
          ),
          borderRadius: BorderRadius.circular(20.r),
          boxShadow: isLocked
              ? [
                  BoxShadow(
                    color: AppColors.accentOrange.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock,
              color: isLocked ? AppColors.white : AppColors.textLight,
              size: 32.r,
            ),
            SizedBox(width: 15.w),
            Text(
              context.tr('lock'),
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.w700,
                color: isLocked ? AppColors.white : AppColors.textLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnlockButton() {
    return GestureDetector(
      onTap: () {
        setState(() => isLocked = false);
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(25.r),
        decoration: BoxDecoration(
          gradient: !isLocked
              ? const LinearGradient(
                  colors: [_successGreen, _successGreenDark],
                )
              : null,
          color: !isLocked ? null : AppColors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: !isLocked
                ? AppColors.transparent
                : AppColors.accentCyan.withValues(alpha: 0.2),
          ),
          borderRadius: BorderRadius.circular(20.r),
          boxShadow: !isLocked
              ? [
                  BoxShadow(
                    color: _successGreen.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_open,
              color: !isLocked ? AppColors.white : AppColors.textLight,
              size: 32.r,
            ),
            SizedBox(width: 15.w),
            Text(
              context.tr('unlock'),
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.w700,
                color: !isLocked ? AppColors.white : AppColors.textLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEngineButton() {
    return GestureDetector(
      onTap: () {
        if (!isLocked) {
          setState(() => engineRunning = !engineRunning);
        }
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(25.r),
        decoration: BoxDecoration(
          gradient: engineRunning
              ? const LinearGradient(
                  colors: [AppColors.accentCyan, _blueDark],
                )
              : null,
          color: engineRunning ? null : AppColors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: engineRunning
                ? AppColors.transparent
                : AppColors.accentCyan.withValues(alpha: 0.2),
          ),
          borderRadius: BorderRadius.circular(20.r),
          boxShadow: engineRunning
              ? [
                  BoxShadow(
                    color: AppColors.accentCyan.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.power_settings_new,
              color: engineRunning
                  ? AppColors.white
                  : AppColors.textLight.withValues(
                      alpha: isLocked ? 0.3 : 1,
                    ),
              size: 32.r,
            ),
            SizedBox(width: 15.w),
            Text(
              engineRunning ? context.tr('stop_engine') : context.tr('start_engine'),
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.w700,
                color: engineRunning
                    ? AppColors.white
                    : AppColors.textLight.withValues(
                        alpha: isLocked ? 0.3 : 1,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.w700,
            color: AppColors.textLight,
          ),
        ),
        SizedBox(height: 15.h),
        Row(
          children: [
            _buildQuickAction(Icons.ac_unit, 'Climate', () {}),
            SizedBox(width: 15.w),
            _buildQuickAction(Icons.local_parking, 'Find Car', () {}),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickAction(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(20.r),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.05),
            border: Border.all(
              color: AppColors.accentCyan.withValues(alpha: 0.2),
            ),
            borderRadius: BorderRadius.circular(15.r),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppColors.accentCyan, size: 32.r),
              SizedBox(height: 10.h),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: AppColors.textLight,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
