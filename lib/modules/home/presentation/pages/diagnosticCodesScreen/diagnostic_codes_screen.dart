import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_routes.dart';
import '../../../../../core/localization/app_localizations.dart';

class DiagnosticCodesScreen extends StatefulWidget {
  const DiagnosticCodesScreen({super.key});

  @override
  State<DiagnosticCodesScreen> createState() => _DiagnosticCodesScreenState();
}

class _DiagnosticCodesScreenState extends State<DiagnosticCodesScreen> {
  String selectedFilter = 'All';

  final List<Map<String, dynamic>> diagnosticCodes = [
    {
      'code': 'P0420',
      'title': 'Catalyst System Efficiency Below Threshold',
      'title_ar': 'كفاءة نظام المحفز أدنى من الحد المقبول',
      'severity': 'critical',
      'system': 'Engine',
      'system_ar': 'المحرك',
      'description': 'Bank 1 catalytic converter is not working efficiently',
      'description_ar': 'المحول الحفاز في البنك 1 لا يعمل بكفاءة كافية',
    },
    {
      'code': 'P0171',
      'title': 'System Too Lean (Bank 1)',
      'title_ar': 'النظام هزيل للغاية (البنك 1)',
      'severity': 'warning',
      'system': 'Engine',
      'system_ar': 'المحرك',
      'description': 'Engine is running with too much air or not enough fuel',
      'description_ar': 'يعمل المحرك بنسبة هواء زائدة أو كمية وقود ناقصة',
    },
    {
      'code': 'C1201',
      'title': 'ABS Control Module Malfunction',
      'title_ar': 'عطل في وحدة التحكم بنظام ABS',
      'severity': 'critical',
      'system': 'ABS',
      'system_ar': 'ABS',
      'description': 'Anti-lock brake system control module has detected a fault',
      'description_ar': 'وحدة التحكم في نظام منع الانزلاق اكتشفت خللاً في النظام',
    },
    {
      'code': 'U0100',
      'title': 'Lost Communication with ECM/PCM',
      'title_ar': 'انقطاع الاتصال مع وحدة التحكم ECM/PCM',
      'severity': 'warning',
      'system': 'Transmission',
      'system_ar': 'ناقل الحركة',
      'description': 'Communication lost with engine control module',
      'description_ar': 'انقطع الاتصال مع وحدة التحكم الإلكترونية في المحرك',
    },
    {
      'code': 'P0301',
      'title': 'Cylinder 1 Misfire Detected',
      'title_ar': 'اكتشاف خلل في اشتعال الأسطوانة 1',
      'severity': 'info',
      'system': 'Engine',
      'system_ar': 'المحرك',
      'description': 'Engine cylinder 1 is not firing properly',
      'description_ar': 'الأسطوانة رقم 1 في المحرك لا تشتعل بشكل صحيح',
    },
  ];

  final List<String> filters = ['All', 'Engine', 'ABS', 'Transmission'];

  List<Map<String, dynamic>> get filteredCodes {
    if (selectedFilter == 'All') {
      return diagnosticCodes;
    }
    return diagnosticCodes
        .where((code) => code['system'] == selectedFilter)
        .toList();
  }

  static const Color _severityCritical = Color(0xFFFF1744);
  static const Color _severityWarning = Color(0xFFFF6B35);
  static const Color _severityInfo = Color(0xFFFFD600);

  Color getSeverityColor(String severity) {
    switch (severity) {
      case 'critical':
        return _severityCritical;
      case 'warning':
        return _severityWarning;
      case 'info':
        return _severityInfo;
      default:
        return AppColors.accentCyan;
    }
  }

  IconData getSeverityIcon(String severity) {
    switch (severity) {
      case 'critical':
        return Icons.error;
      case 'warning':
        return Icons.warning;
      case 'info':
        return Icons.info;
      default:
        return Icons.check_circle;
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
              _buildSummary(),
              _buildFilters(),
              Expanded(
                child: _buildCodesList(),
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
            context.tr('diagnostic_codes'),
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.clear_all, color: AppColors.accentCyan),
            onPressed: _showClearCodesDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final critical =
        diagnosticCodes.where((c) => c['severity'] == 'critical').length;
    final warning =
        diagnosticCodes.where((c) => c['severity'] == 'warning').length;
    final info = diagnosticCodes.where((c) => c['severity'] == 'info').length;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem(context.tr('severity_critical'), critical, _severityCritical),
          _buildSummaryItem(context.tr('severity_warning'), warning, _severityWarning),
          _buildSummaryItem(context.tr('severity_info'), info, _severityInfo),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 32.sp,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        SizedBox(height: 5.h),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
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
              setState(() {
                selectedFilter = filter;
              });
            },
            child: Container(
              margin: EdgeInsets.only(right: 10.w),
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [
                          AppColors.accentCyan,
                          AppColors.accentOrange,
                        ],
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

  Widget _buildCodesList() {
    final codes = filteredCodes;

    if (codes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 80.r,
              color: const Color(0xFF00E676).withValues(alpha: 0.5),
            ),
            SizedBox(height: 20.h),
            Text(
              'No codes found',
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
      itemCount: codes.length,
      itemBuilder: (context, index) {
        final code = codes[index];
        return _buildCodeItem(code, index);
      },
    );
  }

  Widget _buildCodeItem(Map<String, dynamic> code, int index) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final title = isArabic
        ? (code['title_ar'] ?? code['title']) as String
        : code['title'] as String;
    final description = isArabic
        ? (code['description_ar'] ?? code['description']) as String
        : code['description'] as String;
    final system = isArabic
        ? (code['system_ar'] ?? code['system']) as String
        : code['system'] as String;
    final severityColor = getSeverityColor(code['severity'] as String);

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
      child: GestureDetector(
        onTap: () {
          Navigator.pushNamed(
            context,
            AppRoutes.codeDetail,
            arguments: code,
          );
        },
        child: Container(
          margin: EdgeInsets.only(bottom: 15.h),
          padding: EdgeInsets.all(20.r),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.03),
            border: Border.all(
              color: severityColor.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 6.h,
                    ),
                    decoration: BoxDecoration(
                      color: severityColor.withValues(alpha: 0.2),
                      border: Border.all(color: severityColor),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text(
                      code['code'] as String,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        color: severityColor,
                      ),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 10.w,
                      vertical: 6.h,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentCyan.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text(
                      system,
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColors.accentCyan,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    getSeverityIcon(code['severity'] as String),
                    color: severityColor,
                    size: 24.r,
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textLight,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13.sp,
                  color: AppColors.textLight.withValues(alpha: 0.7),
                  height: 1.4,
                ),
              ),
              SizedBox(height: 12.h),
              Row(
                children: [
                  const Spacer(),
                  Text(
                    'View Details',
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColors.accentCyan,
                      fontWeight: FontWeight.w600,
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
            ],
          ),
        ),
      ),
    );
  }

  void _showClearCodesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        title: const Text(
          'Clear Codes?',
          style: TextStyle(color: AppColors.textLight),
        ),
        content: const Text(
          'Are you sure you want to clear all diagnostic codes? This action cannot be undone.',
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
              // Clear codes logic
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentOrange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.r),
              ),
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
