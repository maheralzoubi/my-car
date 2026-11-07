import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../data/models/service_type.dart';
import '../bloc/roadside_bloc.dart';
import '../bloc/roadside_event.dart';
import '../bloc/roadside_state.dart';
import 'roadside_error_snackbar.dart';
import 'tracking_screen.dart';

class SearchingDriverScreen extends StatefulWidget {
  const SearchingDriverScreen({super.key});

  @override
  State<SearchingDriverScreen> createState() => _SearchingDriverScreenState();
}

class _SearchingDriverScreenState extends State<SearchingDriverScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _rotateCtrl;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _rotateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    // A submit that fails fast (offline, photo upload rejected) can finish
    // before this screen subscribes, so the listener never sees the
    // searching -> estimate transition. Leave the same way it would.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<RoadsideBloc>().state;
      if (state.phase == RoadsidePhase.estimate && state.error != null) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _rotateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<RoadsideBloc, RoadsideState>(
      // Only a searching -> estimate transition (submit failed) means leave;
      // draft edits still in the queue when this screen opens don't.
      listenWhen: (prev, curr) =>
          curr.phase != RoadsidePhase.estimate || prev.phase == RoadsidePhase.searching,
      listener: (context, state) {
        if (state.phase == RoadsidePhase.tracking) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const TrackingScreen()),
          );
        } else if (state.phase == RoadsidePhase.idle) {
          Navigator.of(context).popUntil((r) => r.isFirst);
        } else if (state.phase == RoadsidePhase.estimate) {
          // Submit failed; the estimate screen underneath shows the error.
          Navigator.of(context).pop();
        } else if (state.error != null) {
          // The backend refused to cancel; the request is still live.
          setState(() => _cancelling = false);
          showRoadsideError(context, state.error!);
        }
      },
      child: BlocBuilder<RoadsideBloc, RoadsideState>(
        builder: (context, state) {
          final service = state.selectedService;
          final color = service?.color ?? AppColors.accentOrange;

          return Scaffold(
            backgroundColor: AppColors.backgroundDark,
            body: SafeArea(
              child: Column(
                children: [
                  // Cancel bar
                  Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                    child: Row(
                      children: [
                        const Spacer(),
                        TextButton(
                          // Waits for the backend (the idle listener pops);
                          // also held until the request exists, so a cancel
                          // can't race the create call.
                          onPressed: _cancelling || state.isSubmitting
                              ? null
                              : () {
                                  setState(() => _cancelling = true);
                                  context
                                      .read<RoadsideBloc>()
                                      .add(const CancelRequest());
                                },
                          child: _cancelling
                              ? SizedBox(
                                  width: 16.r,
                                  height: 16.r,
                                  child: const CircularProgressIndicator(
                                      strokeWidth: 2, color: AppColors.error),
                                )
                              : Text(context.tr('cancel'),
                                  style: TextStyle(
                                      color: AppColors.error,
                                      fontSize: 14.sp)),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Radar animation
                  SizedBox(
                    width: 240.w,
                    height: 240.w,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Pulsing rings
                        ...List.generate(3, (i) {
                          return AnimatedBuilder(
                            animation: _pulseCtrl,
                            builder: (_, __) {
                              final progress =
                                  (_pulseCtrl.value + i / 3) % 1.0;
                              final size = 60.w + progress * 160.w;
                              return Opacity(
                                opacity: (1 - progress) * 0.4,
                                child: Container(
                                  width: size,
                                  height: size,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: color, width: 2),
                                  ),
                                ),
                              );
                            },
                          );
                        }),

                        // Rotating dashes
                        AnimatedBuilder(
                          animation: _rotateCtrl,
                          builder: (_, __) => Transform.rotate(
                            angle: _rotateCtrl.value * 2 * pi,
                            child: CustomPaint(
                              size: Size(200.w, 200.w),
                              painter: _RadarSweepPainter(color),
                            ),
                          ),
                        ),

                        // Center icon
                        Container(
                          width: 64.w,
                          height: 64.w,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color.withValues(alpha: 0.15),
                            border: Border.all(
                                color: color.withValues(alpha: 0.6),
                                width: 2),
                          ),
                          child: Icon(
                            service?.icon ?? Icons.car_repair,
                            color: color,
                            size: 28.r,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 40.h),

                  Text(
                    context.tr('finding_nearest_driver'),
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 20.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'Looking for ${service?.label ?? 'roadside'} specialists\nnear your location',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textLight.withValues(alpha: 0.6),
                      fontSize: 13.sp,
                    ),
                  ),

                  SizedBox(height: 32.h),

                  // Stats row
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32.w),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: _StatItem(
                            value: '12',
                            label: context.tr('drivers_online'),
                            color: AppColors.accentCyan,
                          ),
                        ),
                        Container(
                            width: 1,
                            height: 32.h,
                            color: AppColors.outline.withValues(alpha: 0.3)),
                        Expanded(
                          child: _StatItem(
                            value: '< 5 km',
                            label: context.tr('search_radius_label'),
                            color: AppColors.accentOrange,
                          ),
                        ),
                        Container(
                            width: 1,
                            height: 32.h,
                            color: AppColors.outline.withValues(alpha: 0.3)),
                        Expanded(
                          child: _StatItem(
                            value: '~${service?.etaMinutes ?? 15} min',
                            label: context.tr('avg_arrival'),
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Bottom note
                  Padding(
                    padding:
                        EdgeInsets.fromLTRB(24.w, 0, 24.w, 24.h),
                    child: Container(
                      padding: EdgeInsets.all(14.r),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDarkElevated,
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              color: AppColors.accentCyan, size: 18.r),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: Text(
                              'You will be notified as soon as a driver accepts your request. Average wait: 2–4 minutes.',
                              style: TextStyle(
                                  color: AppColors.textLight
                                      .withValues(alpha: 0.7),
                                  fontSize: 12.sp),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _StatItem({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                color: color, fontSize: 16.sp, fontWeight: FontWeight.bold)),
        SizedBox(height: 4.h),
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textLight.withValues(alpha: 0.5),
                fontSize: 11.sp)),
      ],
    );
  }
}

class _RadarSweepPainter extends CustomPainter {
  final Color color;
  const _RadarSweepPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final paint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.3),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 0.9, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _RadarSweepPainter old) =>
      old.color != color;
}
