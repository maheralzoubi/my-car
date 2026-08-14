import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../data/models/service_request.dart';
import '../../data/models/service_type.dart';
import '../../roadside_service.dart';

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
    _historyFuture = RoadsideService.instance.repository.getHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.white,
        title: Text(context.tr('request_history_title'),
            style:
                TextStyle(fontSize: 17.sp, fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: FutureBuilder<List<ServiceRequest>>(
        future: _historyFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.accentCyan));
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_rounded,
                      color: AppColors.outline, size: 64.r),
                  SizedBox(height: 16.h),
                  Text(context.tr('no_requests_yet'),
                      style: TextStyle(
                          color: AppColors.textLight.withValues(alpha: 0.5),
                          fontSize: 16.sp)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 32.h),
            itemCount: items.length,
            separatorBuilder: (_, __) => SizedBox(height: 10.h),
            itemBuilder: (_, i) => _HistoryCard(request: items[i]),
          );
        },
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final ServiceRequest request;
  const _HistoryCard({required this.request});

  Color get _statusColor {
    switch (request.status) {
      case RequestStatus.completed:
        return AppColors.success;
      case RequestStatus.cancelled:
        return AppColors.error;
      default:
        return AppColors.accentCyan;
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
    final color = request.serviceType.color;

    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: AppColors.surfaceDarkElevated,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 48.r,
            height: 48.r,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(request.serviceType.icon, color: color, size: 24.r),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request.serviceType.label,
                    style: TextStyle(
                        color: AppColors.white,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600)),
                SizedBox(height: 2.h),
                Text(request.customerAddress,
                    style: TextStyle(
                        color: AppColors.textLight.withValues(alpha: 0.5),
                        fontSize: 11.sp),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                SizedBox(height: 4.h),
                Text(
                  _formatDate(request.createdAt),
                  style: TextStyle(
                      color: AppColors.textLight.withValues(alpha: 0.4),
                      fontSize: 11.sp),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Text(_statusLabel,
                    style: TextStyle(
                        color: _statusColor,
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w600)),
              ),
              SizedBox(height: 6.h),
              Text(
                '\$${(request.estimatedPrice + 5).toStringAsFixed(0)}',
                style: TextStyle(
                    color: AppColors.white,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold),
              ),
              if (request.rating != null) ...[
                SizedBox(height: 4.h),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded,
                        color: const Color(0xFFFFD700), size: 12.r),
                    SizedBox(width: 2.w),
                    Text('${request.rating}',
                        style: TextStyle(
                            color: const Color(0xFFFFD700),
                            fontSize: 11.sp)),
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = dt.hour > 12 ? dt.hour - 12 : dt.hour == 0 ? 12 : dt.hour;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final m = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}  $h:$m $ampm';
  }
}
