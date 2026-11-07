import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/core.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../data/models/service_request.dart';
import '../../data/models/service_type.dart';
import '../bloc/roadside_bloc.dart';
import '../widgets/roadside_visuals.dart';

class RequestHistoryScreen extends StatefulWidget {
  const RequestHistoryScreen({super.key});

  @override
  State<RequestHistoryScreen> createState() => _RequestHistoryScreenState();
}

class _RequestHistoryScreenState extends State<RequestHistoryScreen> {
  late Future<List<ServiceRequest>> _historyFuture;

  @override
  void initState() {
    super.initState();
    // Same repository as the request flow (the live backend), not the
    // RoadsideService mock.
    _historyFuture = context.read<RoadsideBloc>().repository.getHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(title: context.tr('request_history_title')),
            Expanded(
              child: FutureBuilder<List<ServiceRequest>>(
                future: _historyFuture,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final items = snap.data ?? [];
                  if (items.isEmpty) {
                    return EmptyState(
                      icon: Icons.history_rounded,
                      title: context.tr('no_requests_yet'),
                    );
                  }
                  return ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      AppSizes.space20.w,
                      AppSizes.space4.h,
                      AppSizes.space20.w,
                      AppSizes.space24.h,
                    ),
                    itemCount: items.length,
                    separatorBuilder: (_, __) =>
                        SizedBox(height: AppSizes.space12.h),
                    itemBuilder: (_, i) => _HistoryCard(request: items[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final ServiceRequest request;
  const _HistoryCard({required this.request});

  StatusLevel get _statusLevel {
    switch (request.status) {
      case RequestStatus.completed:
        return StatusLevel.ok;
      case RequestStatus.cancelled:
        return StatusLevel.critical;
      default:
        return StatusLevel.info;
    }
  }

  String get _statusLabel {
    switch (request.status) {
      case RequestStatus.completed:
        return 'Completed';
      case RequestStatus.cancelled:
        return 'Cancelled';
      default:
        return 'In Progress';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBox(request.serviceType.icon, size: 44),
          SizedBox(width: AppSizes.space12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.serviceType.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  request.customerAddress,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.label.copyWith(
                    color: p.text2,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  _formatDate(request.createdAt),
                  style: AppTextStyles.caption.copyWith(color: p.muted),
                ),
              ],
            ),
          ),
          SizedBox(width: AppSizes.space8.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusBadge(label: _statusLabel, level: _statusLevel),
              SizedBox(height: AppSizes.space8.h),
              Text(
                '\$${(request.estimatedPrice + 5).toStringAsFixed(0)}',
                style: AppTextStyles.numeric(
                  AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
              ),
              if (request.rating != null) ...[
                SizedBox(height: 2.h),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star_rounded,
                      color: RoadsideVisuals.ratingStar,
                      size: 14.r,
                    ),
                    SizedBox(width: 2.w),
                    Text(
                      '${request.rating}',
                      style: AppTextStyles.caption.copyWith(color: p.text2),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = dt.hour > 12
        ? dt.hour - 12
        : dt.hour == 0
        ? 12
        : dt.hour;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final m = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}  $h:$m $ampm';
  }
}
