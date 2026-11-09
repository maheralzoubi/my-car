import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/localization/app_localizations.dart';

class DashCamSettingsScreen extends StatefulWidget {
  const DashCamSettingsScreen({super.key});

  @override
  State<DashCamSettingsScreen> createState() => _DashCamSettingsScreenState();
}

class _DashCamSettingsScreenState extends State<DashCamSettingsScreen> {
  bool _enabled = true;
  bool _loopRecording = true;
  bool _autoStart = false;
  bool _incidentDetection = true;
  String _videoQuality = '1080p HD';

  static const Color _successGreen = Color(0xFF00E676);
  static const Color _successGreenDark = Color(0xFF00C853);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.backgroundDark, AppColors.backgroundDarkBlue],
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
                      _buildStatusCard(),
                      SizedBox(height: 24.h),
                      _buildSectionTitle(context.tr('dashcam_section_recording')),
                      _buildToggle(
                        '📹',
                        context.tr('dash_cam'),
                        context.tr('dash_cam_sub'),
                        _enabled,
                        (v) => setState(() => _enabled = v),
                      ),
                      _buildToggle(
                        '🔁',
                        context.tr('loop_recording'),
                        context.tr('loop_recording_sub'),
                        _loopRecording,
                        _enabled ? (v) => setState(() => _loopRecording = v) : null,
                      ),
                      _buildToggle(
                        '▶️',
                        context.tr('auto_start_recording'),
                        context.tr('auto_start_sub'),
                        _autoStart,
                        _enabled ? (v) => setState(() => _autoStart = v) : null,
                      ),
                      SizedBox(height: 24.h),
                      _buildSectionTitle(context.tr('dashcam_section_quality')),
                      _buildSelector(
                        '🎥',
                        context.tr('video_quality'),
                        context.tr('video_quality_sub'),
                        _videoQuality,
                        ['720p', '1080p HD'],
                        _enabled ? (v) => setState(() => _videoQuality = v) : null,
                      ),
                      SizedBox(height: 24.h),
                      _buildSectionTitle(context.tr('dashcam_section_safety')),
                      _buildToggle(
                        '🛑',
                        context.tr('incident_detection'),
                        context.tr('incident_detection_sub'),
                        _incidentDetection,
                        _enabled ? (v) => setState(() => _incidentDetection = v) : null,
                      ),
                      SizedBox(height: 20.h),
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
            icon: const Icon(Icons.arrow_back, color: AppColors.accentCyan),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            context.tr('dash_cam_settings'),
            style: TextStyle(
              fontSize: 22.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _enabled
              ? [
                  AppColors.accentCyan.withValues(alpha: 0.12),
                  AppColors.accentOrange.withValues(alpha: 0.05),
                ]
              : [
                  AppColors.white.withValues(alpha: 0.04),
                  AppColors.white.withValues(alpha: 0.02),
                ],
        ),
        border: Border.all(
          color: _enabled
              ? AppColors.accentCyan.withValues(alpha: 0.35)
              : AppColors.white.withValues(alpha: 0.1),
        ),
        borderRadius: BorderRadius.circular(18.r),
      ),
      child: Row(
        children: [
          Container(
            width: 52.r,
            height: 52.r,
            decoration: BoxDecoration(
              color: (_enabled ? AppColors.accentCyan : AppColors.white)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: Icon(
              _enabled ? Icons.videocam : Icons.videocam_off,
              color: _enabled ? AppColors.accentCyan : AppColors.white.withValues(alpha: 0.4),
              size: 28.r,
            ),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(_enabled ? 'dashcam_active' : 'dashcam_disabled'),
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w700,
                    color: _enabled ? AppColors.accentCyan : AppColors.textLight.withValues(alpha: 0.5),
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  _enabled
                      ? '$_videoQuality · ${context.tr(_loopRecording ? 'dashcam_loop_on' : 'dashcam_loop_off')}'
                      : context.tr('dashcam_enable_hint'),
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.textLight.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Row(
        children: [
          Container(
            width: 4.w,
            height: 18.h,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.accentCyan, AppColors.accentOrange],
              ),
              borderRadius: BorderRadius.all(Radius.circular(10.r)),
            ),
          ),
          SizedBox(width: 10.w),
          Text(
            title,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle(
    String icon,
    String title,
    String subtitle,
    bool value,
    void Function(bool)? onChanged,
  ) {
    final disabled = onChanged == null;
    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: disabled ? 0.02 : 0.05),
        border: Border.all(
          color: AppColors.white.withValues(alpha: disabled ? 0.06 : 0.1),
        ),
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Row(
        children: [
          Text(icon, style: TextStyle(fontSize: 22.sp, color: disabled ? null : null)),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: disabled
                        ? AppColors.textLight.withValues(alpha: 0.35)
                        : AppColors.textLight,
                  ),
                ),
                SizedBox(height: 3.h),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.textLight.withValues(alpha: disabled ? 0.25 : 0.55),
                  ),
                ),
              ],
            ),
          ),
          _buildSwitch(value, onChanged),
        ],
      ),
    );
  }

  Widget _buildSelector(
    String icon,
    String title,
    String subtitle,
    String current,
    List<String> options,
    void Function(String)? onChanged,
  ) {
    final disabled = onChanged == null;
    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: disabled ? 0.02 : 0.05),
        border: Border.all(
          color: AppColors.white.withValues(alpha: disabled ? 0.06 : 0.1),
        ),
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: TextStyle(fontSize: 22.sp)),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: disabled
                            ? AppColors.textLight.withValues(alpha: 0.35)
                            : AppColors.textLight,
                      ),
                    ),
                    SizedBox(height: 3.h),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColors.textLight.withValues(alpha: disabled ? 0.25 : 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!disabled) ...[
            SizedBox(height: 14.h),
            Row(
              children: options.map((opt) {
                final selected = opt == current;
                return GestureDetector(
                  onTap: () => onChanged(opt),
                  child: Container(
                    margin: EdgeInsetsDirectional.only(end: 10.w),
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      gradient: selected
                          ? const LinearGradient(
                              colors: [AppColors.accentCyan, AppColors.accentOrange],
                            )
                          : null,
                      color: selected ? null : AppColors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(
                        color: selected
                            ? AppColors.accentCyan
                            : AppColors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Text(
                      opt,
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        color: selected ? AppColors.white : AppColors.textLight.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSwitch(bool value, void Function(bool)? onChanged) {
    return GestureDetector(
      onTap: onChanged != null ? () => onChanged(!value) : null,
      child: Container(
        width: 54.w,
        height: 30.h,
        decoration: BoxDecoration(
          gradient: (value && onChanged != null)
              ? const LinearGradient(colors: [_successGreen, _successGreenDark])
              : null,
          color: (value && onChanged != null)
              ? null
              : AppColors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: value
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          child: Container(
            width: 26.w,
            height: 26.h,
            margin: EdgeInsets.all(2.r),
            decoration: BoxDecoration(
              color: onChanged != null ? AppColors.white : AppColors.white.withValues(alpha: 0.3),
              shape: BoxShape.circle,
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
            ),
          ),
        ),
      ),
    );
  }
}
