import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/core.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../data/models/service_type.dart';
import '../bloc/roadside_bloc.dart';
import '../bloc/roadside_event.dart';
import '../bloc/roadside_state.dart';
import '../widgets/roadside_visuals.dart';
import 'location_picker_screen.dart';
import 'request_history_screen.dart';

/// Roadside tab root: the services a driver can be requested for, plus a link
/// to past requests.
class RoadsideHomeScreen extends StatelessWidget {
  const RoadsideHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<RoadsideBloc, RoadsideState>(
      listener: (context, state) {
        // Only while this screen is on top: the bloc keeps emitting
        // locationPicker states (a repeated tap, a failed price estimate)
        // after the picker is already open.
        if (state.phase == RoadsidePhase.locationPicker &&
            (ModalRoute.of(context)?.isCurrent ?? true)) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
          );
        }
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              ScreenHeader(
                title: context.tr('roadside_assistance'),
                subtitle: context.tr('select_service_needed'),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    AppSizes.space20.w,
                    AppSizes.space4.h,
                    AppSizes.space20.w,
                    AppSizes.space24.h,
                  ),
                  children: [
                    const _FactsCard(),
                    SizedBox(height: AppSizes.space24.h),
                    SectionTitle(
                      context.tr('roadside_services'),
                      trailing: SectionLink(
                        label: context.tr('my_requests'),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const RequestHistoryScreen(),
                          ),
                        ),
                      ),
                    ),
                    for (final type in ServiceType.values) ...[
                      _ServiceCard(serviceType: type),
                      if (type != ServiceType.values.last)
                        SizedBox(height: AppSizes.space12.h),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Average wait, certified drivers and rating, in one quiet row.
class _FactsCard extends StatelessWidget {
  const _FactsCard();

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    Widget divider() =>
        Container(width: 1, height: 32.h, color: p.border);
    return AppCard(
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.space8.w,
        vertical: AppSizes.space12.h,
      ),
      child: Row(
        children: [
          Expanded(
            child: _Fact(
              icon: Icons.schedule_rounded,
              label: context.tr('avg_15_min'),
            ),
          ),
          divider(),
          Expanded(
            child: _Fact(
              icon: Icons.verified_outlined,
              label: context.tr('certified_drivers'),
            ),
          ),
          divider(),
          Expanded(
            child: _Fact(
              icon: Icons.star_rounded,
              label: context.tr('rating_48'),
              iconColor: RoadsideVisuals.ratingStar,
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, this.iconColor});

  final IconData icon;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20.r, color: iconColor ?? p.primary),
        SizedBox(height: AppSizes.space4.h),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.label.copyWith(color: p.text2),
        ),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final ServiceType serviceType;

  const _ServiceCard({required this.serviceType});

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return AppCard(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSizes.space16.w,
        AppSizes.space12.h,
        AppSizes.space8.w,
        AppSizes.space12.h,
      ),
      onTap: () {
        context.read<RoadsideBloc>().add(SelectService(serviceType));
      },
      child: Row(
        children: [
          IconBox(serviceType.icon, size: 44),
          SizedBox(width: AppSizes.space12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  serviceType.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  serviceType.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.label.copyWith(
                    fontWeight: FontWeight.w400,
                    color: p.text2,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: AppSizes.space8.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.tr('price_from'),
                style: AppTextStyles.caption.copyWith(color: p.muted),
              ),
              Text(
                '\$${serviceType.basePrice.toInt()}',
                style: AppTextStyles.numeric(
                  AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
              ),
            ],
          ),
          Icon(Icons.chevron_right_rounded, size: 22.r, color: p.muted),
        ],
      ),
    );
  }
}
