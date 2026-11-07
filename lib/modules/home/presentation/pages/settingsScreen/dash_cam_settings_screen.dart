import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/core.dart';
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

  static const _qualities = ['720p', '1080p HD'];

  /// Opacity of the quality row while the dash cam is off (matches the
  /// disabled [SettingsTile] rows).
  static const double _disabledOpacity = 0.5;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(title: context.tr('dash_cam_settings')),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppSizes.space20.w,
                  AppSizes.space4.h,
                  AppSizes.space20.w,
                  AppSizes.space32.h,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSizes.space24.h,
                  children: [
                    _buildStatusCard(),
                    SettingsGroup(
                      title: context.tr('dashcam_section_recording'),
                      children: [
                        SettingsTile.toggle(
                          leading: const IconBox.neutral(
                            Icons.videocam_outlined,
                          ),
                          title: context.tr('dash_cam'),
                          subtitle: context.tr('dash_cam_sub'),
                          value: _enabled,
                          onChanged: (v) => setState(() => _enabled = v),
                        ),
                        SettingsTile.toggle(
                          leading: const IconBox.neutral(Icons.repeat_rounded),
                          title: context.tr('loop_recording'),
                          subtitle: context.tr('loop_recording_sub'),
                          value: _loopRecording,
                          onChanged: _enabled
                              ? (v) => setState(() => _loopRecording = v)
                              : null,
                        ),
                        SettingsTile.toggle(
                          leading: const IconBox.neutral(
                            Icons.play_circle_outline_rounded,
                          ),
                          title: context.tr('auto_start_recording'),
                          subtitle: context.tr('auto_start_sub'),
                          value: _autoStart,
                          onChanged: _enabled
                              ? (v) => setState(() => _autoStart = v)
                              : null,
                        ),
                      ],
                    ),
                    SettingsGroup(
                      title: context.tr('dashcam_section_quality'),
                      children: [_buildQualityRow()],
                    ),
                    SettingsGroup(
                      title: context.tr('dashcam_section_safety'),
                      children: [
                        SettingsTile.toggle(
                          leading: const IconBox.neutral(
                            Icons.car_crash_outlined,
                          ),
                          title: context.tr('incident_detection'),
                          subtitle: context.tr('incident_detection_sub'),
                          value: _incidentDetection,
                          onChanged: _enabled
                              ? (v) => setState(() => _incidentDetection = v)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final p = context.colors;
    return AppCard(
      child: Row(
        children: [
          _enabled
              ? const IconBox(Icons.videocam_rounded, size: 48)
              : const IconBox.neutral(Icons.videocam_off_rounded, size: 48),
          SizedBox(width: AppSizes.space16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(_enabled ? 'dashcam_active' : 'dashcam_disabled'),
                  style: AppTextStyles.title.copyWith(color: p.text),
                ),
                SizedBox(height: 2.h),
                Text(
                  _enabled
                      ? '$_videoQuality · ${context.tr(_loopRecording ? 'dashcam_loop_on' : 'dashcam_loop_off')}'
                      : context.tr('dashcam_enable_hint'),
                  style: AppTextStyles.label.copyWith(
                    fontWeight: FontWeight.w400,
                    color: p.text2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Title + segmented control. The control is hidden while the dash cam is
  /// off, and the row fades like the disabled toggles.
  Widget _buildQualityRow() {
    final p = context.colors;
    return Opacity(
      opacity: _enabled ? 1 : _disabledOpacity,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.space16.w,
          vertical: AppSizes.space12.h,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const IconBox.neutral(Icons.hd_outlined),
                SizedBox(width: AppSizes.space12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('video_quality'),
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w500,
                          color: p.text,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        context.tr('video_quality_sub'),
                        style: AppTextStyles.label.copyWith(
                          fontWeight: FontWeight.w400,
                          color: p.text2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_enabled) ...[
              SizedBox(height: AppSizes.space12.h),
              AppSegmentedControl<String>(
                segments: [for (final q in _qualities) (q, q)],
                value: _videoQuality,
                onChanged: (v) => setState(() => _videoQuality = v),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
