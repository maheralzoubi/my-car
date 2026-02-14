import 'package:flutter/material.dart';

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
                      padding: const EdgeInsets.all(20),
                      child: SizedBox(
                        width: width,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildVideoInfo(),
                            const SizedBox(height: 20),
                            _buildInstructorInfo(),
                            const SizedBox(height: 25),
                            _buildDescription(),
                            const SizedBox(height: 25),
                            _buildToolsAndParts(),
                            const SizedBox(height: 25),
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
      padding: const EdgeInsets.all(20.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.accentCyan),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(
              Icons.picture_in_picture_alt,
              color: AppColors.accentCyan,
            ),
            onPressed: _showPIPDialog,
          ),
          IconButton(
            icon: const Icon(Icons.share, color: AppColors.accentCyan),
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
      margin: const EdgeInsets.symmetric(horizontal: 20),
      height: 220,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
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
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Text(
                thumbnail,
                style: const TextStyle(fontSize: 80),
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
                width: 70,
                height: 70,
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
                  size: 40,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
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
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        duration,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 12,
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
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: AppColors.accentCyan.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                code,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentCyan,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textLight,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            const Icon(Icons.visibility, color: AppColors.accentCyan, size: 18),
            const SizedBox(width: 8),
            Text(
              '$views views',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textLight.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 20),
            const Icon(Icons.star, color: _ratingYellow, size: 18),
            const SizedBox(width: 8),
            Text(
              '$rating rating',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textLight.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
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
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.bookmark_border),
                label: const Text('Save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.white.withValues(alpha: 0.1),
                  foregroundColor: _ratingYellow,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.accentCyan, AppColors.accentOrange],
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _instructorLetter,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _instructor,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textLight,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  uploadedBy,
                  style: TextStyle(
                    fontSize: 13,
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
                  borderRadius: BorderRadius.circular(20),
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
              width: 4,
              height: 20,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.accentCyan, AppColors.accentOrange],
                ),
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Description',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        Text(
          'Learn how to properly diagnose and fix the $code error code. This comprehensive tutorial covers everything you need to know, from identifying the problem to completing the repair.',
          style: TextStyle(
            fontSize: 15,
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
              width: 4,
              height: 20,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.accentCyan, AppColors.accentOrange],
                ),
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Tools & Parts Needed',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.accentCyan.withValues(alpha: 0.1),
        border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        tool,
        style: const TextStyle(
          fontSize: 13,
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
              width: 4,
              height: 20,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.accentCyan, AppColors.accentOrange],
                ),
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Related Videos',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 3,
            itemBuilder: (context, index) {
              return Container(
                width: 200,
                margin: const EdgeInsets.only(right: 15),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.05),
                  border: Border.all(
                    color: AppColors.accentCyan.withValues(alpha: 0.2),
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 82,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.accentCyan.withValues(alpha: 0.2),
                            AppColors.accentOrange.withValues(alpha: 0.1),
                          ],
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(15),
                          topRight: Radius.circular(15),
                        ),
                      ),
                      child: const Center(
                        child: Text('🔧', style: TextStyle(fontSize: 40)),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Related Tutorial ${index + 1}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textLight,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '12 min',
                              style: TextStyle(
                                fontSize: 11,
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
          borderRadius: BorderRadius.circular(20),
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
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Enable PIP'),
          ),
        ],
      ),
    );
  }
}
