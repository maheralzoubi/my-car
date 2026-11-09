import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_routes.dart';
import '../../../../../core/localization/app_localizations.dart';
import 'dtc_code_info.dart';

class CodeDetailScreen extends StatefulWidget {
  const CodeDetailScreen({super.key, required this.code});

  /// Route arguments: `code`, `title`, `description`, `system`, `severity`
  /// (+ optional `title_ar`, `description_ar`, `system_ar`) and `pending`
  /// (true for a mode-07 code the ECU has not confirmed yet).
  final Map<String, dynamic> code;

  @override
  State<CodeDetailScreen> createState() => _CodeDetailScreenState();
}

class _CodeDetailScreenState extends State<CodeDetailScreen> {
  static const Color _severityCritical = Color(0xFFFF1744);
  static const Color _severityWarning = Color(0xFFFF6B35);
  static const Color _severityInfo = Color(0xFFFFD600);
  static const Color _pendingColor = Color(0xFFFFD600);

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

  // ── Argument accessors ────────────────────────────────────────────────────

  bool get _isArabic => Localizations.localeOf(context).languageCode == 'ar';

  /// The localized field [key], falling back to the English one.
  String? _field(String key) {
    final v = _isArabic
        ? (widget.code['${key}_ar'] ?? widget.code[key])
        : widget.code[key];
    final s = (v as String?)?.trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  String? get _codeStr {
    final raw = (widget.code['code'] as String?)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw.startsWith('~') ? raw.substring(1) : raw;
  }

  /// null when the caller did not say (e.g. opened from a lookup).
  bool? get _isPending => widget.code['pending'] as bool?;

  String get _title => _field('title') ?? '—';

  /// The description, unless it only repeats the title.
  String? get _description {
    final d = _field('description');
    if (d == null) return _field('title') == null ? '—' : null;
    return d == _field('title') ? null : d;
  }

  DtcCodeInfo get _info => DtcCodeInfo(_codeStr ?? '');

  // ── Share ─────────────────────────────────────────────────────────────────

  Future<void> _share(BuildContext buttonContext) async {
    final code = _codeStr ?? context.tr('diagnostic_code_fallback');
    final info = _info;
    final buf = StringBuffer('$code — $_title');
    final desc = _description;
    if (desc != null && desc != '—') buf.write('\n$desc');
    if (info.categoryKey != null) {
      buf.write('\n${context.tr('dtc_category_label')}: '
          '${context.tr(info.categoryKey!)}');
    }
    if (info.typeKey != null) {
      buf.write('\n${context.tr('dtc_type_label')}: '
          '${context.tr(info.typeKey!)}');
    }
    if (info.subsystemKey != null) {
      buf.write('\n${context.tr('dtc_subsystem_label')}: '
          '${context.tr(info.subsystemKey!)}');
    }
    if (_isPending != null) {
      buf.write('\n${context.tr('dtc_status_label')}: ${context.tr(
          _isPending! ? 'dtc_status_pending' : 'dtc_status_confirmed')}');
    }
    buf.write('\n\n${context.tr('report_generated_by')}');

    final box = buttonContext.findRenderObject() as RenderBox?;
    await Share.share(
      buf.toString(),
      subject: '$code — $_title',
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
                      _buildNextSteps(),
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
          Expanded(
            child: Text(
              context.tr('code_details'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 24.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ),
          Builder(
            builder: (buttonContext) => IconButton(
              icon: Icon(Icons.share, color: AppColors.accentCyan),
              onPressed: () => _share(buttonContext),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeCard(Color severityColor) {
    final system = _field('system') ?? '—';
    final description = _description;
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
                  _codeStr ?? '—',
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColors.accentCyan,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (_isPending == true) ...[
                SizedBox(width: 8.w),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: _pendingColor.withValues(alpha: 0.15),
                    border: Border.all(color: _pendingColor),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(
                    context.tr('dtc_pending'),
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: _pendingColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: 20.h),
          Text(
            _title,
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
              height: 1.3,
            ),
          ),
          if (description != null) ...[
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
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Row(
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
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
        ),
      ],
    );
  }

  /// Facts derived from the code itself (SAE J2012 structure) plus the
  /// status reported by the ECU — nothing guessed about the root cause.
  Widget _buildDetailsSection() {
    final info = _info;
    final pending = _isPending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context.tr('what_this_means')),
        SizedBox(height: 15.h),
        _buildDetailCard(
          '⚠️',
          context.tr('severity_label'),
          context
              .tr('severity_${widget.code['severity'] as String? ?? 'info'}')
              .toUpperCase(),
          getSeverityColor(),
        ),
        if (pending != null)
          _buildDetailCard(
            pending ? '⏳' : '📌',
            context.tr('dtc_status_label'),
            context.tr(
                pending ? 'dtc_status_pending' : 'dtc_status_confirmed'),
            pending ? _pendingColor : AppColors.accentCyan,
          ),
        if (info.categoryKey != null)
          _buildDetailCard(
            '🚗',
            context.tr('dtc_category_label'),
            context.tr(info.categoryKey!),
            AppColors.accentCyan,
          ),
        if (info.typeKey != null)
          _buildDetailCard(
            info.isManufacturerSpecific ? '🏭' : '📘',
            context.tr('dtc_type_label'),
            context.tr(info.typeKey!),
            AppColors.accentCyan,
          ),
        if (info.subsystemKey != null)
          _buildDetailCard(
            '🔍',
            context.tr('dtc_subsystem_label'),
            context.tr(info.subsystemKey!),
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

  Widget _buildNextSteps() {
    final steps = _info.nextStepKeys(isPending: _isPending ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context.tr('dtc_next_steps')),
        SizedBox(height: 15.h),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(18.r),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.05),
            border: Border.all(color: AppColors.white.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(15.r),
          ),
          child: Column(
            children: [
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                      bottom: i == steps.length - 1 ? 0 : 12.h),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(top: 3.h),
                        child: Icon(
                          steps[i] == 'dtc_step_stop'
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline,
                          size: 16.r,
                          color: steps[i] == 'dtc_step_stop'
                              ? _severityWarning
                              : AppColors.accentCyan,
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: Text(
                          context.tr(steps[i]),
                          style: TextStyle(
                            fontSize: 14.sp,
                            color: AppColors.textLight.withValues(alpha: 0.85),
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
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
          context.tr('view_solution').toUpperCase(),
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: _isArabic ? 0 : 2,
            color: AppColors.white,
          ),
        ),
      ),
    );
  }
}
