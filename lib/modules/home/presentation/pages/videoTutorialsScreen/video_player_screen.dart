import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/core.dart';
import '../../../../../core/localization/app_localizations.dart';

/// Screen for playing a tutorial video. Receives [tutorial] from route arguments.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.tutorial});

  final Map<String, dynamic> tutorial;

  /// Builds [VideoPlayerScreen] from [ModalRoute.of(context)?.settings.arguments].
  static Widget fromContext(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final tutorial = args is Map<String, dynamic> ? args : <String, dynamic>{};
    return VideoPlayerScreen(tutorial: tutorial);
  }

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  // Video player chrome. A player keeps a true-black backdrop and white
  // controls regardless of the app theme (video content is theme-independent),
  // so these stay literal colors.
  static const Color _playerBackdrop = Color(0xFF000000);
  static const Color _controlsScrim = Color(0x8C000000); // black @ 55%
  static const Color _playerControl = AppColors.white;
  static const Color _playerControlMuted = Color(0x4DFFFFFF); // white @ 30%
  static const Color _placeholderIcon = Color(0x40FFFFFF); // white @ 25%

  bool isPlaying = false;
  bool isFullscreen = false;
  double currentPosition = 0.0;
  double totalDuration = 100.0;

  String get _instructor => widget.tutorial['instructor'] as String? ?? '—';
  String get _instructorLetter {
    final s = _instructor;
    return s.isNotEmpty ? s.substring(0, 1).toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: context.tr('video_tutorials'),
              actions: [
                HeaderAction(
                  icon: Icons.picture_in_picture_alt_rounded,
                  tooltip: context.tr('pip_mode'),
                  onPressed: _showPIPDialog,
                ),
                HeaderAction(
                  icon: Icons.share_rounded,
                  tooltip: context.tr('share_action'),
                  onPressed: () => _showSnack('tutorial_action_unavailable'),
                ),
              ],
            ),
            _buildVideoPlayer(),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppSizes.space20.w,
                  AppSizes.space20.h,
                  AppSizes.space20.w,
                  AppSizes.space32.h,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildVideoInfo(),
                    SizedBox(height: AppSizes.space16.h),
                    _buildActions(),
                    SizedBox(height: AppSizes.space16.h),
                    _buildInstructorInfo(),
                    SizedBox(height: AppSizes.space24.h),
                    _buildDescription(),
                    SizedBox(height: AppSizes.space24.h),
                    _buildToolsAndParts(),
                    SizedBox(height: AppSizes.space24.h),
                    _buildRelatedVideos(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    final duration = widget.tutorial['duration'] as String? ?? '0:00';
    final icon =
        widget.tutorial['icon'] as IconData? ?? Icons.ondemand_video_rounded;
    final timeStyle = AppTextStyles.numeric(
      AppTextStyles.label,
    ).copyWith(color: _playerControl);
    final position =
        '${(currentPosition / 60).floor()}:'
        '${(currentPosition % 60).floor().toString().padLeft(2, '0')}';

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSizes.space20.w),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSizes.radiusLg.r),
        child: Container(
          height: 200.h,
          color: _playerBackdrop,
          child: Stack(
            children: [
              // Placeholder artwork: there is no video frame to show.
              PositionedDirectional(
                top: AppSizes.space16.r,
                start: AppSizes.space16.r,
                child: ExcludeSemantics(
                  child: Icon(icon, size: 28.r, color: _placeholderIcon),
                ),
              ),
              Align(
                alignment: const Alignment(0, -0.25),
                child: Material(
                  color: _playerControl,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      setState(() => isPlaying = !isPlaying);
                      // There is no video source behind the sample catalogue.
                      if (isPlaying) _showSnack('video_playback_unavailable');
                    },
                    child: Tooltip(
                      message: context.tr(
                        isPlaying ? 'pause_video' : 'play_video',
                      ),
                      child: SizedBox.square(
                        dimension: 60.r,
                        child: Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: _playerBackdrop,
                          size: 34.r,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                bottom: 0,
                start: 0,
                end: 0,
                child: Container(
                  color: _controlsScrim,
                  padding: EdgeInsetsDirectional.fromSTEB(
                    AppSizes.space12.w,
                    0,
                    AppSizes.space12.w,
                    AppSizes.space8.h,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: _playerControl,
                          inactiveTrackColor: _playerControlMuted,
                          thumbColor: _playerControl,
                          overlayColor: _playerControlMuted,
                          trackHeight: 3,
                        ),
                        child: Slider(
                          value: currentPosition,
                          max: totalDuration,
                          onChanged: (value) {
                            setState(() => currentPosition = value);
                          },
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSizes.space12.w,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(position, style: timeStyle),
                            Text(duration, style: timeStyle),
                          ],
                        ),
                      ),
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

  Widget _buildVideoInfo() {
    final p = context.colors;
    final code = widget.tutorial['code'] as String? ?? '—';
    final title = widget.tutorial['title'] as String? ?? '—';
    final views = widget.tutorial['views'] as String? ?? '—';
    final rating = widget.tutorial['rating']?.toString() ?? '—';
    final metaStyle = AppTextStyles.label.copyWith(
      fontWeight: FontWeight.w400,
      color: p.text2,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: AppSizes.space8.w,
            vertical: 2.h,
          ),
          decoration: BoxDecoration(
            color: p.primarySoft,
            borderRadius: BorderRadius.circular(6.r),
          ),
          child: Text(
            code,
            style: AppTextStyles.label.copyWith(
              fontWeight: FontWeight.w600,
              color: p.primary,
            ),
          ),
        ),
        SizedBox(height: AppSizes.space8.h),
        Text(title, style: AppTextStyles.headline.copyWith(color: p.text)),
        SizedBox(height: AppSizes.space8.h),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSizes.space4.w,
          runSpacing: AppSizes.space4.h,
          children: [
            Icon(Icons.visibility_outlined, color: p.muted, size: 16.r),
            Text(
              context.tr('views_count').replaceAll('{n}', views),
              style: metaStyle,
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSizes.space4.w),
              child: Text('·', style: metaStyle.copyWith(color: p.muted)),
            ),
            Icon(Icons.star_rounded, color: p.muted, size: 16.r),
            Text(
              context.tr('rating_value').replaceAll('{n}', rating),
              style: metaStyle,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: AppButton.secondary(
            label: context.tr('like'),
            icon: Icons.thumb_up_outlined,
            compact: true,
            onPressed: () => _showSnack('tutorial_action_unavailable'),
          ),
        ),
        SizedBox(width: AppSizes.space12.w),
        Expanded(
          child: AppButton.secondary(
            label: context.tr('save'),
            icon: Icons.bookmark_border_rounded,
            compact: true,
            onPressed: () => _showSnack('tutorial_action_unavailable'),
          ),
        ),
      ],
    );
  }

  Widget _buildInstructorInfo() {
    final p = context.colors;
    final uploadedBy = widget.tutorial['uploadedBy'] as String? ?? '—';

    return AppCard(
      padding: EdgeInsets.all(AppSizes.space12.r),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 44.r,
              height: 44.r,
              decoration: BoxDecoration(
                color: p.primarySoft,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                _instructorLetter,
                style: AppTextStyles.title.copyWith(color: p.primary),
              ),
            ),
          ),
          SizedBox(width: AppSizes.space12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _instructor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
                Text(
                  uploadedBy,
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
          AppButton.secondary(
            label: context.tr('subscribe'),
            compact: true,
            expand: false,
            onPressed: () => _showSnack('tutorial_action_unavailable'),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription() {
    final code = widget.tutorial['code'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(context.tr('description_label')),
        Text(
          context.tr('tutorial_description_body').replaceAll('{code}', code),
          style: AppTextStyles.body.copyWith(color: context.colors.text2),
        ),
      ],
    );
  }

  Widget _buildToolsAndParts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(context.tr('tools_parts_needed')),
        Wrap(
          spacing: AppSizes.space8.w,
          runSpacing: AppSizes.space8.h,
          children: [
            _buildToolChip(
              Icons.handyman_outlined,
              context.tr('tool_socket_set'),
            ),
            _buildToolChip(Icons.sensors_rounded, context.tr('tool_o2_sensor')),
            _buildToolChip(
              Icons.water_drop_outlined,
              context.tr('tool_anti_seize'),
            ),
            _buildToolChip(
              Icons.back_hand_outlined,
              context.tr('tool_safety_gloves'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildToolChip(IconData icon, String tool) {
    final p = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.space12.w,
        vertical: AppSizes.space8.h,
      ),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16.r, color: p.text2),
          SizedBox(width: 6.w),
          Text(tool, style: AppTextStyles.label.copyWith(color: p.text)),
        ],
      ),
    );
  }

  Widget _buildRelatedVideos() {
    final p = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(context.tr('related_videos')),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: AppSizes.space16.w,
                    color: p.border,
                  ),
                Padding(
                  padding: EdgeInsets.all(AppSizes.space12.r),
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: Container(
                          width: 64.r,
                          height: 44.r,
                          decoration: BoxDecoration(
                            color: p.surface2,
                            borderRadius: BorderRadius.circular(
                              AppSizes.radiusSm.r,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.play_circle_outline_rounded,
                            size: 22.r,
                            color: p.text2,
                          ),
                        ),
                      ),
                      SizedBox(width: AppSizes.space12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context
                                  .tr('related_tutorial_n')
                                  .replaceAll('{n}', '${i + 1}'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.body.copyWith(
                                fontWeight: FontWeight.w500,
                                color: p.text,
                              ),
                            ),
                            Text(
                              context.tr('minutes_n').replaceAll('{n}', '12'),
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
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Honest feedback for controls with nothing behind them yet (sample
  /// catalogue, no video plugin or tutorial backend).
  void _showSnack(String key) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.tr(key))));
  }

  void _showPIPDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('pip_mode')),
        content: Text(context.tr('pip_prompt')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSnack('pip_unavailable');
            },
            child: Text(context.tr('enable_pip')),
          ),
        ],
      ),
    );
  }
}
