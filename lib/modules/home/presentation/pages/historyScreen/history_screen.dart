import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/localization/app_localizations.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String selectedFilter = 'All';

  static const Color _criticalRed = Color(0xFFFF1744);
  static const Color _successGreen = Color(0xFF00E676);

  late List<Map<String, dynamic>> _scanHistory;

  @override
  void initState() {
    super.initState();
    _scanHistory = [
      {
        'date': 'Today, 2:30 PM',
        'result': '2 codes detected',
        'status': 'warning',
        'codes': ['P0420', 'C1201'],
        'vehicle': 'Toyota Camry 2020',
      },
      {
        'date': 'Yesterday, 10:15 AM',
        'result': 'No issues found',
        'status': 'success',
        'codes': [],
        'vehicle': 'Toyota Camry 2020',
      },
      {
        'date': 'Jan 28, 4:20 PM',
        'result': '1 code detected',
        'status': 'warning',
        'codes': ['P0171'],
        'vehicle': 'Toyota Camry 2020',
      },
      {
        'date': 'Jan 25, 9:00 AM',
        'result': 'No issues found',
        'status': 'success',
        'codes': [],
        'vehicle': 'Toyota Camry 2020',
      },
      {
        'date': 'Jan 20, 3:45 PM',
        'result': '3 codes detected',
        'status': 'critical',
        'codes': ['P0420', 'P0171', 'U0100'],
        'vehicle': 'Toyota Camry 2020',
      },
    ];
  }

  final List<String> filters = ['All', 'Critical', 'Warning', 'Success'];

  List<Map<String, dynamic>> get filteredHistory {
    if (selectedFilter == 'All') {
      return _scanHistory;
    }
    return _scanHistory
        .where((scan) =>
            scan['status'].toString().toLowerCase() ==
            selectedFilter.toLowerCase())
        .toList();
  }

  Color getStatusColor(String status) {
    switch (status) {
      case 'critical':
        return _criticalRed;
      case 'warning':
        return AppColors.accentOrange;
      case 'success':
        return _successGreen;
      default:
        return AppColors.accentCyan;
    }
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
              _buildStats(),
              _buildFilters(),
              Expanded(
                child: _buildHistoryList(),
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
            context.tr('history_title'),
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.delete_outline, color: AppColors.accentOrange),
            onPressed: _showClearHistoryDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final total = _scanHistory.length;
    final critical =
        _scanHistory.where((s) => s['status'] == 'critical').length;
    final warning = _scanHistory.where((s) => s['status'] == 'warning').length;
    final success = _scanHistory.where((s) => s['status'] == 'success').length;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.white.withValues(alpha: 0.05),
            AppColors.white.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(
          color: AppColors.accentCyan.withValues(alpha: 0.2),
        ),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(context.tr('all'), total, AppColors.accentCyan),
              _buildStatItem(context.tr('severity_critical'), critical, _criticalRed),
              _buildStatItem(context.tr('severity_warning'), warning, AppColors.accentOrange),
              _buildStatItem(context.tr('connected'), success, _successGreen),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 28.sp,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        SizedBox(height: 5.h),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.sp,
            color: AppColors.textLight.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Container(
      height: 50.h,
      margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = selectedFilter == filter;

          return GestureDetector(
            onTap: () {
              setState(() => selectedFilter = filter);
            },
            child: Container(
              margin: EdgeInsets.only(right: 10.w),
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [AppColors.accentCyan, AppColors.accentOrange],
                      )
                    : null,
                color: isSelected ? null : AppColors.white.withValues(alpha: 0.05),
                border: Border.all(
                  color: isSelected
                      ? AppColors.transparent
                      : AppColors.accentCyan.withValues(alpha: 0.2),
                ),
                borderRadius: BorderRadius.circular(25.r),
              ),
              child: Center(
                child: Text(
                  filter,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? AppColors.white
                        : AppColors.textLight,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistoryList() {
    final history = filteredHistory;

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 80.r,
              color: AppColors.accentCyan.withValues(alpha: 0.3),
            ),
            SizedBox(height: 20.h),
            Text(
              context.tr('no_history'),
              style: TextStyle(
                fontSize: 18.sp,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(20.r),
      itemCount: history.length,
      itemBuilder: (context, index) {
        return _buildHistoryItem(history[index], index);
      },
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> scan, int index) {
    final statusColor = getStatusColor(scan['status'] as String);
    final codes = scan['codes'] as List<dynamic>? ?? [];

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 100)),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(50 * (1 - value), 0),
            child: child,
          ),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 15.h),
        padding: EdgeInsets.all(20.r),
        decoration: BoxDecoration(
          color: AppColors.white.withValues(alpha: 0.03),
          border: Border.all(
            color: statusColor.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scan['date'] as String? ?? '—',
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: AppColors.accentCyan,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 5.h),
                      Text(
                        scan['vehicle'] as String? ?? '—',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.textLight.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.w,
                    vertical: 6.h,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    border: Border.all(color: statusColor),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    scan['status'] == 'success'
                        ? 'Clean'
                        : '${codes.length} Code${codes.length > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 15.h),
            Text(
              scan['result'] as String? ?? '—',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.textLight,
              ),
            ),
            if (codes.isNotEmpty) ...[
              SizedBox(height: 12.h),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: codes.map<Widget>((code) {
                  return Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 10.w,
                      vertical: 5.h,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.white.withValues(alpha: 0.05),
                      border: Border.all(
                        color: AppColors.accentCyan.withValues(alpha: 0.3),
                      ),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Text(
                      code.toString(),
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentCyan,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            SizedBox(height: 12.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    // View details
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View Details',
                        style: TextStyle(
                          color: AppColors.accentCyan,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.sp,
                        ),
                      ),
                      SizedBox(width: 5.w),
                      Icon(
                        Icons.arrow_forward,
                        color: AppColors.accentCyan,
                        size: 16.r,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showClearHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        title: const Text(
          'Clear History?',
          style: TextStyle(color: AppColors.textLight),
        ),
        content: const Text(
          'Are you sure you want to clear all scan history? This action cannot be undone.',
          style: TextStyle(color: AppColors.textLight),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.accentCyan),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _scanHistory.clear());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentOrange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.r),
              ),
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}
