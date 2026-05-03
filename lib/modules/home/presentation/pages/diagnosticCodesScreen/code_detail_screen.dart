import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_routes.dart';

class CodeDetailScreen extends StatefulWidget {
  const CodeDetailScreen({super.key, required this.code});

  final Map<String, dynamic> code;

  @override
  State<CodeDetailScreen> createState() => _CodeDetailScreenState();
}

class _CodeDetailScreenState extends State<CodeDetailScreen> {
  final List<String> images = ['🔧', '🔩', '⚙️', '🛠️'];

  static const Color _severityCritical = Color(0xFFFF1744);
  static const Color _severityWarning = Color(0xFFFF6B35);
  static const Color _severityInfo = Color(0xFFFFD600);

  Color getSeverityColor() {
    switch (widget.code['severity']) {
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

  @override
  Widget build(BuildContext context) {
    final severityColor = getSeverityColor();

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
                      _buildCodeCard(severityColor),
                      SizedBox(height: 25.h),
                      _buildDetailsSection(),
                      SizedBox(height: 25.h),
                      _buildImageGallery(),
                      SizedBox(height: 25.h),
                      _buildRelatedCodes(),
                      SizedBox(height: 25.h),
                      _buildActionButton(),
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
            'Code Details',
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.share, color: AppColors.accentCyan),
            onPressed: () {
              // Share functionality
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCodeCard(Color severityColor) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final title = isArabic
        ? (widget.code['title_ar'] ?? widget.code['title']) as String? ?? '—'
        : widget.code['title'] as String? ?? '—';
    final description = isArabic
        ? (widget.code['description_ar'] ?? widget.code['description']) as String? ?? '—'
        : widget.code['description'] as String? ?? '—';
    final system = isArabic
        ? (widget.code['system_ar'] ?? widget.code['system']) as String? ?? '—'
        : widget.code['system'] as String? ?? '—';
    return Container(
      padding: EdgeInsets.all(25.r),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            severityColor.withValues(alpha: 0.15),
            severityColor.withValues(alpha: 0.05),
          ],
        ),
        border: Border.all(
          color: severityColor.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(25.r),
        boxShadow: [
          BoxShadow(
            color: severityColor.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 16.w,
                  vertical: 10.h,
                ),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.2),
                  border: Border.all(color: severityColor, width: 2),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  widget.code['code'] as String? ?? '—',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w900,
                    color: severityColor,
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.w,
                    vertical: 8.h,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentCyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Text(
                    system,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColors.accentCyan,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 20.h),
          Text(
            title,
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
              height: 1.3,
            ),
          ),
          SizedBox(height: 12.h),
          Text(
            description,
            style: TextStyle(
              fontSize: 15.sp,
              color: AppColors.textLight.withValues(alpha: 0.7),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4.w,
              height: 20.h,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.accentCyan, AppColors.accentOrange],
                ),
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
            SizedBox(width: 10.w),
            Text(
              'What This Means',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        SizedBox(height: 15.h),
        _buildDetailCard(
          '⚠️',
          'Severity',
          (widget.code['severity'] as String? ?? 'info').toUpperCase(),
          getSeverityColor(),
        ),
        _buildDetailCard(
          '🔍',
          'Cause',
          'Faulty oxygen sensor or catalytic converter malfunction',
          AppColors.accentCyan,
        ),
        _buildDetailCard(
          '💰',
          'Estimated Cost',
          '\$200 - \$800',
          _severityInfo,
        ),
        _buildDetailCard(
          '⏱️',
          'Repair Time',
          '2-4 hours',
          AppColors.accentCyan,
        ),
      ],
    );
  }

  Widget _buildDetailCard(
    String icon,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(18.r),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: AppColors.white.withValues(alpha: 0.1),
        ),
        borderRadius: BorderRadius.circular(15.r),
      ),
      child: Row(
        children: [
          Container(
            width: 45.w,
            height: 45.h,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Center(
              child: Text(icon, style: TextStyle(fontSize: 22.sp)),
            ),
          ),
          SizedBox(width: 15.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.textLight.withValues(alpha: 0.6),
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGallery() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4.w,
              height: 20.h,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.accentCyan, AppColors.accentOrange],
                ),
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
            SizedBox(width: 10.w),
            Text(
              'Related Images',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        SizedBox(height: 15.h),
        SizedBox(
          height: 120.h,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            itemBuilder: (context, index) {
              return Container(
                width: 120.w,
                margin: EdgeInsets.only(right: 15.w),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.accentCyan.withValues(alpha: 0.2),
                      AppColors.accentOrange.withValues(alpha: 0.1),
                    ],
                  ),
                  border: Border.all(
                    color: AppColors.accentCyan.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(15.r),
                ),
                child: Center(
                  child: Text(
                    images[index],
                    style: TextStyle(fontSize: 48.sp),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRelatedCodes() {
    final relatedCodes = ['P0171', 'P0174', 'P0430'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4.w,
              height: 20.h,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.accentCyan, AppColors.accentOrange],
                ),
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
            SizedBox(width: 10.w),
            Text(
              'Related Codes',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        SizedBox(height: 15.h),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: relatedCodes.map((code) {
            return Container(
              padding: EdgeInsets.symmetric(
                horizontal: 16.w,
                vertical: 10.h,
              ),
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.05),
                border: Border.all(
                  color: AppColors.accentCyan.withValues(alpha: 0.3),
                ),
                borderRadius: BorderRadius.circular(20.r),
              ),
              child: Text(
                code,
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentCyan,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildActionButton() {
    return Container(
      width: double.infinity,
      height: 56.h,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.accentCyan, AppColors.accentOrange],
        ),
        borderRadius: BorderRadius.circular(15.r),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentCyan.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: () {
          Navigator.pushNamed(
            context,
            AppRoutes.solution,
            arguments: widget.code,
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.transparent,
          shadowColor: AppColors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15.r),
          ),
        ),
        child: Text(
          'VIEW SOLUTION',
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: AppColors.white,
          ),
        ),
      ),
    );
  }
}
