import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/core.dart';
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<RoadsideBloc, RoadsideState>(
      // Only a searching -> estimate transition (submit failed) means leave;
      // draft edits still in the queue when this screen opens don't.
      listenWhen: (prev, curr) =>
          curr.phase != RoadsidePhase.estimate ||
          prev.phase == RoadsidePhase.searching,
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
          final p = context.colors;
          final service = state.selectedService;

          return Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  ScreenHeader(
                    title: service?.label ?? context.tr('roadside_assistance'),
                    showBack: false,
                    actions: [
                      _CancelButton(
                        cancelling: _cancelling,
                        // Waits for the backend (the idle listener pops);
                        // also held until the request exists, so a cancel
                        // can't race the create call.
                        onPressed: _cancelling || state.isSubmitting
                            ? null
                            : () {
                                setState(() => _cancelling = true);
                                context.read<RoadsideBloc>().add(
                                  const CancelRequest(),
                                );
                              },
                      ),
                    ],
                  ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSizes.space20.w,
                          vertical: AppSizes.space16.h,
                        ),
                        child: Column(
                          children: [
                            _Pulse(
                              animation: _pulseCtrl,
                              icon: service?.icon ?? Icons.car_repair,
                            ),
                            SizedBox(height: AppSizes.space24.h),
                            Text(
                              context.tr('finding_nearest_driver'),
                              textAlign: TextAlign.center,
                              style: AppTextStyles.headline.copyWith(
                                color: p.text,
                              ),
                            ),
                            SizedBox(height: AppSizes.space8.h),
                            Text(
                              'Looking for ${service?.label ?? 'roadside'} specialists\nnear your location',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.body.copyWith(
                                color: p.text2,
                              ),
                            ),
                            SizedBox(height: AppSizes.space24.h),
                            _StatsCard(etaMinutes: service?.etaMinutes ?? 15),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSizes.space20.w,
                      0,
                      AppSizes.space20.w,
                      AppSizes.space16.h,
                    ),
                    child: AppCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: p.primary,
                            size: 20.r,
                          ),
                          SizedBox(width: AppSizes.space12.w),
                          Expanded(
                            child: Text(
                              'You will be notified as soon as a driver accepts your request. Average wait: 2–4 minutes.',
                              style: AppTextStyles.label.copyWith(
                                color: p.text2,
                                fontWeight: FontWeight.w400,
                              ),
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

/// Header action: red "Cancel" text, or a spinner while the backend answers.
class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.cancelling, required this.onPressed});

  final bool cancelling;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: p.crit,
        minimumSize: Size(44.r, 44.r),
      ),
      child: cancelling
          ? SizedBox.square(
              dimension: 16.r,
              child: CircularProgressIndicator(strokeWidth: 2, color: p.crit),
            )
          : Text(
              context.tr('cancel'),
              style: AppTextStyles.body.copyWith(
                fontWeight: FontWeight.w600,
                color: p.crit,
              ),
            ),
    );
  }
}

/// Calm "searching" indicator: rings expanding from the service icon.
class _Pulse extends StatelessWidget {
  const _Pulse({required this.animation, required this.icon});

  final Animation<double> animation;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final box = 200.r;
    return SizedBox.square(
      dimension: box,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ...List.generate(3, (i) {
            return AnimatedBuilder(
              animation: animation,
              builder: (_, __) {
                final progress = (animation.value + i / 3) % 1.0;
                final size = 80.r + progress * (box - 80.r);
                return Opacity(
                  opacity: (1 - progress) * 0.6,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: p.primary, width: 1.5),
                    ),
                  ),
                );
              },
            );
          }),
          Container(
            width: 80.r,
            height: 80.r,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.primarySoft,
            ),
            child: Icon(icon, color: p.primary, size: 36.r),
          ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.etaMinutes});

  final int etaMinutes;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    Widget divider() => Container(width: 1, height: 36.h, color: p.border);
    return AppCard(
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.space8.w,
        vertical: AppSizes.space16.h,
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatItem(value: '12', label: context.tr('drivers_online')),
          ),
          divider(),
          Expanded(
            child: _StatItem(
              value: '< 5 km',
              label: context.tr('search_radius_label'),
            ),
          ),
          divider(),
          Expanded(
            child: _StatItem(
              value: '~$etaMinutes min',
              label: context.tr('avg_arrival'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;

  const _StatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          style: AppTextStyles.numeric(
            AppTextStyles.title.copyWith(color: p.text),
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: AppTextStyles.caption.copyWith(color: p.text2),
        ),
      ],
    );
  }
}
