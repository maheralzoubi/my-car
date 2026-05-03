import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/constants/app_colors.dart';

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
  static const Color _ratingYellow = Color(0xFFFFD600);

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
              _buildVideoPlayer(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : MediaQuery.of(context).size.width;
                    return SingleChildScrollView(
                      padding: EdgeInsets.all(20.r),
                      child: SizedBox(
                        width: width,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildVideoInfo(),
                            SizedBox(height: 20.h),
                            _buildInstructorInfo(),
                            SizedBox(height: 25.h),
                            _buildDescription(),
                            SizedBox(height: 25.h),
                            _buildToolsAndParts(),
                            SizedBox(height: 25.h),
                            _buildRelatedVideos(),
                          ],
                        ),
                      ),
                    );
                  },
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
            icon: Icon(Icons.arrow_back, color: AppColors.accentCyan, size: 24.r),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              Icons.picture_in_picture_alt,
              color: AppColors.accentCyan,
              size: 24.r,
            ),
            onPressed: _showPIPDialog,
          ),
          IconButton(
            icon: Icon(Icons.share, color: AppColors.accentCyan, size: 24.r),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer() {
    final duration = widget.tutorial['duration'] as String? ?? '0:00';
    final thumbnail = widget.tutorial['thumbnail'] as String? ?? '🎬';

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20.w),
      height: 220.h,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
          ),
        ],
      ),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.accentCyan.withValues(alpha: 0.3),
                  AppColors.accentOrange.withValues(alpha: 0.2),
                ],
              ),
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Center(
              child: Text(
                thumbnail,
                style: TextStyle(fontSize: 80.sp),
              ),
            ),
          ),
          Center(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  isPlaying = !isPlaying;
                });
              },
              child: Container(
                width: 70.w,
                height: 70.h,
                decoration: BoxDecoration(
                  color: AppColors.accentCyan.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accentCyan.withValues(alpha: 0.5),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: AppColors.white,
                  size: 40.r,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.all(15.r),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20.r),
                  bottomRight: Radius.circular(20.r),
                ),
              ),
              child: Column(
                children: [
                  Slider(
                    value: currentPosition,
                    max: totalDuration,
                    activeColor: AppColors.accentCyan,
                    inactiveColor: AppColors.white.withValues(alpha: 0.3),
                    onChanged: (value) {
                      setState(() {
                        currentPosition = value;
                      });
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${(currentPosition / 60).floor()}:${(currentPosition % 60).floor().toString().padLeft(2, '0')}',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 12.sp,
                        ),
                      ),
                      Text(
                        duration,
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 12.sp,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoInfo() {
    final code = widget.tutorial['code'] as String? ?? '—';
    final title = widget.tutorial['title'] as String? ?? '—';
    final views = widget.tutorial['views'] as String? ?? '—';
    final rating = widget.tutorial['rating']?.toString() ?? '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: 10.w,
                vertical: 6.h,
              ),
              decoration: BoxDecoration(
                color: AppColors.accentCyan.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                code,
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentCyan,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 15.h),
        Text(
          title,
          style: TextStyle(
            fontSize: 22.sp,
            fontWeight: FontWeight.w700,
            color: AppColors.textLight,
            height: 1.3,
          ),
        ),
        SizedBox(height: 15.h),
        Row(
          children: [
            Icon(Icons.visibility, color: AppColors.accentCyan, size: 18.r),
            SizedBox(width: 8.w),
            Text(
              '$views views',
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColors.textLight.withValues(alpha: 0.7),
              ),
            ),
            SizedBox(width: 20.w),
            Icon(Icons.star, color: _ratingYellow, size: 18.r),
            SizedBox(width: 8.w),
            Text(
              '$rating rating',
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColors.textLight.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        SizedBox(height: 15.h),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.thumb_up_outlined),
                label: const Text('Like'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.white.withValues(alpha: 0.1),
                  foregroundColor: AppColors.accentCyan,
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.bookmark_border),
                label: const Text('Save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.white.withValues(alpha: 0.1),
                  foregroundColor: _ratingYellow,
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInstructorInfo() {
    final uploadedBy = widget.tutorial['uploadedBy'] as String? ?? '—';

    return Container(
      padding: EdgeInsets.all(18.r),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(15.r),
      ),
      child: Row(
        children: [
          Container(
            width: 50.w,
            height: 50.h,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.accentCyan, AppColors.accentOrange],
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _instructorLetter,
                style: TextStyle(
                  fontSize: 24.sp,
                  fontWeight: FontWeight.w900,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
          SizedBox(width: 15.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _instructor,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textLight,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  uploadedBy,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColors.textLight.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            fit: FlexFit.loose,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentCyan,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20.r),
                ),
              ),
              child: const Text(
                'Subscribe',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
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
        Row(
          children: [
            Container(
              width: 4.w,
              height: 20.h,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.accentCyan, AppColors.accentOrange],
                ),
                borderRadius: BorderRadius.all(Radius.circular(10.r)),
              ),
            ),
            SizedBox(width: 10.w),
            Text(
              'Description',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        SizedBox(height: 15.h),
        Text(
          'Learn how to properly diagnose and fix the $code error code. This comprehensive tutorial covers everything you need to know, from identifying the problem to completing the repair.',
          style: TextStyle(
            fontSize: 15.sp,
            color: AppColors.textLight.withValues(alpha: 0.8),
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _buildToolsAndParts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4.w,
              height: 20.h,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.accentCyan, AppColors.accentOrange],
                ),
                borderRadius: BorderRadius.all(Radius.circular(10.r)),
              ),
            ),
            SizedBox(width: 10.w),
            Text(
              'Tools & Parts Needed',
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
          children: [
            _buildToolChip('Socket Set'),
            _buildToolChip('O2 Sensor'),
            _buildToolChip('Anti-Seize'),
            _buildToolChip('Safety Gloves'),
          ],
        ),
      ],
    );
  }

  Widget _buildToolChip(String tool) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: AppColors.accentCyan.withValues(alpha: 0.1),
        border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Text(
        tool,
        style: TextStyle(
          fontSize: 13.sp,
          color: AppColors.accentCyan,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildRelatedVideos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4.w,
              height: 20.h,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.accentCyan, AppColors.accentOrange],
                ),
                borderRadius: BorderRadius.all(Radius.circular(10.r)),
              ),
            ),
            SizedBox(width: 10.w),
            Text(
              'Related Videos',
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
          height: 160.h,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 3,
            itemBuilder: (context, index) {
              return Container(
                width: 200.w,
                margin: EdgeInsets.only(right: 15.w),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.05),
                  border: Border.all(
                    color: AppColors.accentCyan.withValues(alpha: 0.2),
                  ),
                  borderRadius: BorderRadius.circular(15.r),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 82.h,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.accentCyan.withValues(alpha: 0.2),
                            AppColors.accentOrange.withValues(alpha: 0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(15.r),
                          topRight: Radius.circular(15.r),
                        ),
                      ),
                      child: Center(
                        child: Text('🔧', style: TextStyle(fontSize: 40.sp)),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10.w,
                          vertical: 6.h,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Related Tutorial ${index + 1}',
                              style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textLight,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 4.h),
                            Text(
                              '12 min',
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: AppColors.textLight.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showPIPDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        title: const Text(
          'Picture-in-Picture Mode',
          style: TextStyle(color: AppColors.textLight),
        ),
        content: const Text(
          'Continue watching while browsing other screens?',
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
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentCyan,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.r),
              ),
            ),
            child: const Text('Enable PIP'),
          ),
        ],
      ),
    );
  }
}
