import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/localization/app_localizations.dart';

class ParentModeScreen extends StatefulWidget {
  const ParentModeScreen({super.key});

  @override
  State<ParentModeScreen> createState() => _ParentModeScreenState();
}

class _ParentModeScreenState extends State<ParentModeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool locationTracking = true;
  bool speedAlerts = true;
  bool geoFence = false;
  int speedLimit = 100;

  // DEMO data: there is no live source (no GPS trip feed or backend for a
  // tracked driver), so the screen shows fixed sample values and says so via
  // [_buildDemoNotice]. Display strings are localized in [_buildStatsGrid].
  int currentSpeed = 120;
  static const int _demoDriveMinutes = 135;
  static const int _demoDistanceKm = 145;
  static const int _demoAvgSpeedKmh = 95;

  static const Color _speedAlertRed = Color(0xFFFF1744);
  static const Color _successGreen = Color(0xFF00E676);
  static const Color _successGreenDark = Color(0xFF00C853);

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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDemoNotice(),
                      SizedBox(height: 15.h),
                      _buildMapCard(),
                      SizedBox(height: 25.h),
                      _buildStatsGrid(),
                      SizedBox(height: 30.h),
                      _buildSettingsSection(),
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
            icon: Icon(Icons.arrow_back, color: AppColors.accentCyan, size: 24.r),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            context.tr('parent_mode'),
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapCard() {
    return Container(
      height: 350.h,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accentCyan.withValues(alpha: 0.1),
            AppColors.accentOrange.withValues(alpha: 0.05),
          ],
        ),
        border: Border.all(
          color: AppColors.white.withValues(alpha: 0.15),
        ),
        borderRadius: BorderRadius.circular(30.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 45,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30.r),
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF4A90E2),
                    Color(0xFF7FB3D5),
                    Color(0xFFA9CCE3),
                  ],
                ),
              ),
            ),
            CustomPaint(
              size: const Size(double.infinity, double.infinity),
              painter: _MapGridPainter(),
            ),
            _buildCarMarker(),
            _buildSpeedBadge(),
            if (speedAlerts && currentSpeed > speedLimit) _buildAlertBadge(),
          ],
        ),
      ),
    );
  }

  Widget _buildCarMarker() {
    return Center(
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1 + (_pulseController.value * 1.0),
                child: Container(
                  width: 120.w,
                  height: 120.h,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.accentCyan
                          .withValues(alpha: 1 - _pulseController.value),
                      width: 3,
                    ),
                  ),
                ),
              ),
              Container(
                width: 60.w,
                height: 60.h,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00D9FF), Color(0xFF0066FF)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accentCyan.withValues(alpha: 0.5),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.directions_car,
                  color: AppColors.white,
                  size: 30.r,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSpeedBadge() {
    return PositionedDirectional(
      top: 20,
      end: 20,
      child: Container(
        width: 80.w,
        height: 80.h,
        decoration: BoxDecoration(
          color: AppColors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: _speedAlertRed,
            width: 4,
          ),
          boxShadow: [
            BoxShadow(
              color: _speedAlertRed.withValues(alpha: 0.4),
              blurRadius: 25,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              currentSpeed.toString(),
              style: TextStyle(
                fontSize: 28.sp,
                fontWeight: FontWeight.w900,
                color: _speedAlertRed,
              ),
            ),
            Text(
              context.tr('parent_kmh'),
              style: TextStyle(
                fontSize: 11.sp,
                color: const Color(0xFF666666),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertBadge() {
    return PositionedDirectional(
      bottom: 20,
      start: 20,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: _speedAlertRed,
          borderRadius: BorderRadius.circular(25.r),
          boxShadow: [
            BoxShadow(
              color: _speedAlertRed.withValues(alpha: 0.4),
              blurRadius: 25,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning, color: AppColors.white, size: 20.r),
            SizedBox(width: 8.w),
            Text(
              context.tr('parent_speed_alert'),
              style: TextStyle(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14.sp,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDemoNotice() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: AppColors.accentOrange.withValues(alpha: 0.1),
        border: Border.all(
          color: AppColors.accentOrange.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: AppColors.accentOrange, size: 20.r),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              context.tr('parent_demo_notice'),
              style: TextStyle(fontSize: 13.sp, color: AppColors.textLight),
            ),
          ),
        ],
      ),
    );
  }

  /// Two rows of two cards whose height follows their content (a fixed
  /// GridView aspect ratio overflowed by ~22 px at phone width).
  Widget _buildStatsGrid() {
    final hours = _demoDriveMinutes ~/ 60;
    final minutes = _demoDriveMinutes % 60;
    final cards = [
      _buildStatCard(
        '📍',
        context.tr('parent_current_location'),
        context.tr('parent_demo_location'),
      ),
      _buildStatCard(
        '⏱️',
        context.tr('parent_drive_time'),
        context
            .tr('parent_duration_hm')
            .replaceAll('{h}', '$hours')
            .replaceAll('{m}', '$minutes'),
      ),
      _buildStatCard(
        '🛣️',
        context.tr('parent_distance'),
        context.tr('parent_value_km').replaceAll('{n}', '$_demoDistanceKm'),
      ),
      _buildStatCard(
        '⚡',
        context.tr('parent_avg_speed'),
        context.tr('parent_value_kmh').replaceAll('{n}', '$_demoAvgSpeedKmh'),
      ),
    ];
    Widget row(Widget a, Widget b) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: a),
              const SizedBox(width: 15),
              Expanded(child: b),
            ],
          ),
        );
    return Column(
      children: [
        row(cards[0], cards[1]),
        const SizedBox(height: 15),
        row(cards[2], cards[3]),
      ],
    );
  }

  Widget _buildStatCard(String icon, String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 16.h),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: AppColors.white.withValues(alpha: 0.1),
        ),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(icon, style: TextStyle(fontSize: 32.sp)),
          SizedBox(height: 10.h),
          Text(
            label,
            style: TextStyle(
              fontSize: 13.sp,
              color: AppColors.textLight.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8.h),
          Text(
            value,
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.accentCyan,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4.w,
              height: 20.h,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.accentCyan, AppColors.accentOrange],
                ),
                borderRadius: BorderRadius.all(Radius.circular(10.r)),
              ),
            ),
            SizedBox(width: 10.w),
            Text(
              context.tr('parent_tracking_settings'),
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        SizedBox(height: 15.h),
        _buildSettingCard(
          context.tr('parent_location_tracking'),
          context.tr('parent_location_tracking_sub'),
          locationTracking,
          (value) => setState(() => locationTracking = value),
        ),
        _buildSpeedLimitCard(),
        _buildSettingCard(
          context.tr('parent_speed_alerts'),
          context.tr('parent_speed_alerts_sub'),
          speedAlerts,
          (value) => setState(() => speedAlerts = value),
        ),
        _buildSettingCard(
          context.tr('parent_geo_fence'),
          context.tr('parent_geo_fence_sub'),
          geoFence,
          (value) => setState(() => geoFence = value),
        ),
      ],
    );
  }

  Widget _buildSettingCard(
    String title,
    String description,
    bool value,
    void Function(bool) onChanged,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: 15.h),
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: AppColors.white.withValues(alpha: 0.1),
        ),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textLight,
                  ),
                ),
                SizedBox(height: 5.h),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColors.textLight.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          _buildToggleSwitch(value, onChanged),
        ],
      ),
    );
  }

  Widget _buildSpeedLimitCard() {
    return Container(
      margin: EdgeInsets.only(bottom: 15.h),
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: AppColors.white.withValues(alpha: 0.1),
        ),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('parent_speed_limit'),
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textLight,
                  ),
                ),
                SizedBox(height: 5.h),
                Text(
                  context.tr('parent_alert_when_exceeded'),
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColors.textLight.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 80.w,
            padding: EdgeInsets.symmetric(horizontal: 15.w, vertical: 10.h),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: AppColors.accentCyan.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: TextField(
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              style: TextStyle(
                color: AppColors.accentCyan,
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '100',
                hintStyle: TextStyle(color: AppColors.accentCyan),
              ),
              onChanged: (value) {
                setState(() {
                  speedLimit = int.tryParse(value) ?? 100;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleSwitch(bool value, void Function(bool) onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 60.w,
        height: 32.h,
        decoration: BoxDecoration(
          gradient: value
              ? const LinearGradient(
                  colors: [_successGreen, _successGreenDark],
                )
              : null,
          color: value ? null : AppColors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: value
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          child: Container(
            width: 28.w,
            height: 28.h,
            margin: EdgeInsets.all(2.r),
            decoration: const BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.white.withValues(alpha: 0.1)
      ..strokeWidth = 1;

    const spacing = 40.0;

    for (double i = 0; i < size.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += spacing) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
