import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/core.dart';
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
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(title: context.tr('parent_mode')),
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
                    _buildDemoNotice(),
                    SizedBox(height: AppSizes.space16.h),
                    _buildMapCard(),
                    SizedBox(height: AppSizes.space16.h),
                    _buildStatsGrid(),
                    SizedBox(height: AppSizes.space24.h),
                    _buildSettingsSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Schematic map (no live map source): grid + two roads on a neutral
  /// fill, the tracked car in the middle, speed readout and alert on top.
  Widget _buildMapCard() {
    final p = context.colors;
    return AppCard(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 280.h,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: p.surface2,
                child: CustomPaint(
                  painter: _MapGridPainter(
                    grid: p.border,
                    road: p.borderStrong,
                  ),
                ),
              ),
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
    final p = context.colors;
    return Center(
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1 + _pulseController.value,
                child: Container(
                  width: 64.r,
                  height: 64.r,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: p.primary.withValues(
                        alpha: 1 - _pulseController.value,
                      ),
                      width: 2,
                    ),
                  ),
                ),
              ),
              child!,
            ],
          );
        },
        child: Container(
          width: 52.r,
          height: 52.r,
          decoration: BoxDecoration(
            color: p.primaryButton,
            shape: BoxShape.circle,
            border: Border.all(color: p.surface, width: 3),
          ),
          child: Icon(
            Icons.directions_car_rounded,
            color: p.onPrimary,
            size: 24.r,
          ),
        ),
      ),
    );
  }

  /// Current speed in a speed-limit-sign style disc. The ring is red (a
  /// status color) while the car is over the limit, neutral otherwise.
  Widget _buildSpeedBadge() {
    final p = context.colors;
    final over = currentSpeed > speedLimit;
    final tone = over ? p.crit : p.text;
    return PositionedDirectional(
      top: AppSizes.space16.r,
      end: AppSizes.space16.r,
      child: Container(
        width: 72.r,
        height: 72.r,
        decoration: BoxDecoration(
          color: p.surface,
          shape: BoxShape.circle,
          border: Border.all(color: over ? p.crit : p.borderStrong, width: 4),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              currentSpeed.toString(),
              style: AppTextStyles.headline.copyWith(height: 1.1, color: tone),
            ),
            Text(
              context.tr('unit_kmh'),
              style: AppTextStyles.caption.copyWith(color: p.text2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertBadge() {
    final p = context.colors;
    return PositionedDirectional(
      bottom: AppSizes.space16.r,
      start: AppSizes.space16.r,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.space12.w,
          vertical: AppSizes.space8.h,
        ),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(AppSizes.radiusFull),
          border: Border.all(color: p.crit),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, color: p.crit, size: 18.r),
            SizedBox(width: AppSizes.space8.w),
            Text(
              context.tr('parent_speed_alert'),
              style: AppTextStyles.label.copyWith(
                fontWeight: FontWeight.w600,
                color: p.crit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDemoNotice() {
    final p = context.colors;
    return AppCard(
      accent: p.warn,
      padding: EdgeInsets.all(AppSizes.space12.r),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: p.warn, size: 20.r),
          SizedBox(width: AppSizes.space8.w),
          Expanded(
            child: Text(
              context.tr('parent_demo_notice'),
              style: AppTextStyles.label.copyWith(
                fontWeight: FontWeight.w400,
                color: p.text,
              ),
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
        Icons.location_on_outlined,
        context.tr('parent_current_location'),
        context.tr('parent_demo_location'),
      ),
      _buildStatCard(
        Icons.schedule_rounded,
        context.tr('parent_drive_time'),
        context
            .tr('parent_duration_hm')
            .replaceAll('{h}', '$hours')
            .replaceAll('{m}', '$minutes'),
      ),
      _buildStatCard(
        Icons.route_outlined,
        context.tr('parent_distance'),
        context.tr('parent_value_km').replaceAll('{n}', '$_demoDistanceKm'),
      ),
      _buildStatCard(
        Icons.speed_rounded,
        context.tr('parent_avg_speed'),
        context.tr('parent_value_kmh').replaceAll('{n}', '$_demoAvgSpeedKmh'),
      ),
    ];
    Widget row(Widget a, Widget b) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSizes.space12.w,
        children: [
          Expanded(child: a),
          Expanded(child: b),
        ],
      ),
    );
    return Column(
      spacing: AppSizes.space12.h,
      children: [row(cards[0], cards[1]), row(cards[2], cards[3])],
    );
  }

  Widget _buildStatCard(IconData icon, String label, String value) {
    return StatTile(icon: IconBox(icon, size: 28), label: label, value: value);
  }

  Widget _buildSettingsSection() {
    return SettingsGroup(
      title: context.tr('parent_tracking_settings'),
      children: [
        SettingsTile.toggle(
          leading: const IconBox.neutral(Icons.my_location_rounded),
          title: context.tr('parent_location_tracking'),
          subtitle: context.tr('parent_location_tracking_sub'),
          value: locationTracking,
          onChanged: (value) => setState(() => locationTracking = value),
        ),
        SettingsTile.toggle(
          leading: const IconBox.neutral(Icons.notifications_active_outlined),
          title: context.tr('parent_speed_alerts'),
          subtitle: context.tr('parent_speed_alerts_sub'),
          value: speedAlerts,
          onChanged: (value) => setState(() => speedAlerts = value),
        ),
        _buildSpeedLimitRow(),
        SettingsTile.toggle(
          leading: const IconBox.neutral(Icons.fence_rounded),
          title: context.tr('parent_geo_fence'),
          subtitle: context.tr('parent_geo_fence_sub'),
          value: geoFence,
          onChanged: (value) => setState(() => geoFence = value),
        ),
      ],
    );
  }

  Widget _buildSpeedLimitRow() {
    final valueStyle = AppTextStyles.numeric(
      AppTextStyles.title.copyWith(color: context.colors.text),
    );
    return SettingsTile(
      leading: const IconBox.neutral(Icons.speed_rounded),
      title: context.tr('parent_speed_limit'),
      subtitle: context.tr('parent_alert_when_exceeded'),
      trailing: SizedBox(
        width: 76.w,
        // Fill and borders come from the app's input theme.
        child: TextField(
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          style: valueStyle,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppSizes.space8.w,
              vertical: AppSizes.space12.h,
            ),
            // Reads as the current value until the user types one.
            hintText: '100',
            hintStyle: valueStyle,
          ),
          onChanged: (value) {
            setState(() {
              speedLimit = int.tryParse(value) ?? 100;
            });
          },
        ),
      ),
    );
  }
}

/// Schematic map: a light street grid plus one horizontal and one vertical
/// main road through the center.
class _MapGridPainter extends CustomPainter {
  _MapGridPainter({required this.grid, required this.road});

  final Color grid;
  final Color road;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;

    const spacing = 32.0;

    for (double i = 0; i < size.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    }
    for (double i = 0; i < size.height; i += spacing) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), gridPaint);
    }

    final roadPaint = Paint()
      ..color = road
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    final y = size.height * 0.5;
    final x = size.width * 0.38;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), roadPaint);
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), roadPaint);
  }

  @override
  bool shouldRepaint(covariant _MapGridPainter old) =>
      old.grid != grid || old.road != road;
}
