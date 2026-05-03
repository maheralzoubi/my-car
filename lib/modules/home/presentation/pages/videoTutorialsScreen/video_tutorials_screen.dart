import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_routes.dart';

class VideoTutorialsScreen extends StatefulWidget {
  const VideoTutorialsScreen({super.key});

  @override
  State<VideoTutorialsScreen> createState() => _VideoTutorialsScreenState();
}

class _VideoTutorialsScreenState extends State<VideoTutorialsScreen> {
  String selectedFilter = 'All';
  String selectedDifficulty = 'All';

  static const Color _successGreen = Color(0xFF00E676);
  static const Color _ratingYellow = Color(0xFFFFD600);

  late List<Map<String, dynamic>> _tutorials;

  @override
  void initState() {
    super.initState();
    _tutorials = [
      {
        'id': '1',
        'title': 'How to Replace Oxygen Sensor',
        'code': 'P0420',
        'duration': '15 min',
        'difficulty': 'Intermediate',
        'views': '125K',
        'rating': 4.8,
        'thumbnail': '🔧',
        'instructor': 'Mike Johnson',
        'cost': 'Low (\$50-\$150)',
        'bookmarked': false,
        'uploadedBy': 'CarRepairPro',
      },
      {
        'id': '2',
        'title': 'Fix Engine Misfire - Complete Guide',
        'code': 'P0301',
        'duration': '22 min',
        'difficulty': 'Advanced',
        'views': '89K',
        'rating': 4.9,
        'thumbnail': '⚡',
        'instructor': 'Sarah Miller',
        'cost': 'Medium (\$200-\$500)',
        'bookmarked': true,
        'uploadedBy': 'AutoTechTV',
      },
      {
        'id': '3',
        'title': 'Check Engine Light Diagnosis',
        'code': 'General',
        'duration': '8 min',
        'difficulty': 'Beginner',
        'views': '250K',
        'rating': 4.7,
        'thumbnail': '💡',
        'instructor': 'John Smith',
        'cost': 'Free',
        'bookmarked': false,
        'uploadedBy': 'DIYCar',
      },
      {
        'id': '4',
        'title': 'ABS System Troubleshooting',
        'code': 'C1201',
        'duration': '18 min',
        'difficulty': 'Intermediate',
        'views': '67K',
        'rating': 4.6,
        'thumbnail': '🛞',
        'instructor': 'David Lee',
        'cost': 'Medium (\$300-\$600)',
        'bookmarked': false,
        'uploadedBy': 'AutoRepairHub',
      },
      {
        'id': '5',
        'title': 'How to Clean MAF Sensor',
        'code': 'P0100',
        'duration': '10 min',
        'difficulty': 'Beginner',
        'views': '180K',
        'rating': 4.9,
        'thumbnail': '🌊',
        'instructor': 'Chris Anderson',
        'cost': 'Low (\$10-\$30)',
        'bookmarked': true,
        'uploadedBy': 'QuickFix',
      },
    ];
  }

  List<Map<String, dynamic>> get filteredTutorials {
    return _tutorials.where((tutorial) {
      final matchesFilter = selectedFilter == 'All' ||
          tutorial['code'].toString().contains(selectedFilter);
      final matchesDifficulty = selectedDifficulty == 'All' ||
          tutorial['difficulty'] == selectedDifficulty;
      return matchesFilter && matchesDifficulty;
    }).toList();
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
              _buildSearchBar(),
              _buildFilterChips(),
              Expanded(
                child: _buildTutorialsList(),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _buildUploadButton(),
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
          Text(
            'Video Tutorials',
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.bookmarks, color: AppColors.accentCyan, size: 24.r),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: AppColors.accentCyan.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(15.r),
      ),
      child: TextField(
        style: const TextStyle(color: AppColors.textLight),
        decoration: InputDecoration(
          hintText: 'Search tutorials...',
          hintStyle: TextStyle(
            color: AppColors.textLight.withValues(alpha: 0.5),
          ),
          border: InputBorder.none,
          icon: const Icon(Icons.search, color: AppColors.accentCyan),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Column(
      children: [
        SizedBox(
          height: 50.h,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 5.h),
            children: [
              _buildFilterChip('All', selectedFilter == 'All', () {
                setState(() => selectedFilter = 'All');
              }),
              _buildFilterChip('P0420', selectedFilter == 'P0420', () {
                setState(() => selectedFilter = 'P0420');
              }),
              _buildFilterChip('P0301', selectedFilter == 'P0301', () {
                setState(() => selectedFilter = 'P0301');
              }),
              _buildFilterChip('General', selectedFilter == 'General', () {
                setState(() => selectedFilter = 'General');
              }),
            ],
          ),
        ),
        SizedBox(
          height: 50.h,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 5.h),
            children: [
              _buildFilterChip('All Levels', selectedDifficulty == 'All', () {
                setState(() => selectedDifficulty = 'All');
              }),
              _buildFilterChip('Beginner', selectedDifficulty == 'Beginner', () {
                setState(() => selectedDifficulty = 'Beginner');
              }),
              _buildFilterChip(
                'Intermediate',
                selectedDifficulty == 'Intermediate',
                () => setState(() => selectedDifficulty = 'Intermediate'),
              ),
              _buildFilterChip('Advanced', selectedDifficulty == 'Advanced', () {
                setState(() => selectedDifficulty = 'Advanced');
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
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
            label,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: isSelected ? AppColors.white : AppColors.textLight,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTutorialsList() {
    final filtered = filteredTutorials;

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.video_library_outlined,
              size: 80.r,
              color: AppColors.accentCyan.withValues(alpha: 0.3),
            ),
            SizedBox(height: 20.h),
            Text(
              'No tutorials found',
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
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        return _buildTutorialCard(filtered[index], index);
      },
    );
  }

  Widget _buildTutorialCard(Map<String, dynamic> tutorial, int index) {
    final difficulty = tutorial['difficulty'] as String? ?? '';

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
            AppRoutes.videoPlayer,
            arguments: tutorial,
          );
        },
        child: Container(
          margin: EdgeInsets.only(bottom: 15.h),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.03),
            border: Border.all(
              color: AppColors.accentCyan.withValues(alpha: 0.2),
            ),
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Container(
                    height: 180.h,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.accentCyan.withValues(alpha: 0.2),
                          AppColors.accentOrange.withValues(alpha: 0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20.r),
                        topRight: Radius.circular(20.r),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        tutorial['thumbnail'] as String? ?? '🎬',
                        style: TextStyle(fontSize: 60.sp),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10.w,
                        vertical: 5.h,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        tutorial['duration'] as String? ?? '—',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          tutorial['bookmarked'] =
                              !(tutorial['bookmarked'] as bool? ?? false);
                        });
                      },
                      child: Container(
                        padding: EdgeInsets.all(8.r),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          (tutorial['bookmarked'] as bool? ?? false)
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                          color: (tutorial['bookmarked'] as bool? ?? false)
                              ? _ratingYellow
                              : AppColors.white,
                          size: 20.r,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: EdgeInsets.all(15.r),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8.w,
                            vertical: 4.h,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accentCyan.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          child: Text(
                            tutorial['code'] as String? ?? '—',
                            style: TextStyle(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accentCyan,
                            ),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8.w,
                            vertical: 4.h,
                          ),
                          decoration: BoxDecoration(
                            color: _getDifficultyColor(difficulty)
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          child: Text(
                            difficulty,
                            style: TextStyle(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w600,
                              color: _getDifficultyColor(difficulty),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10.h),
                    Text(
                      tutorial['title'] as String? ?? '—',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textLight,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      'By ${tutorial['instructor'] ?? '—'}',
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: AppColors.textLight.withValues(alpha: 0.7),
                      ),
                    ),
                    SizedBox(height: 10.h),
                    Row(
                      children: [
                        Icon(
                          Icons.star,
                          color: _ratingYellow,
                          size: 16.r,
                        ),
                        SizedBox(width: 5.w),
                        Text(
                          (tutorial['rating'] ?? '—').toString(),
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textLight,
                          ),
                        ),
                        SizedBox(width: 15.w),
                        Icon(
                          Icons.visibility,
                          color: AppColors.accentCyan,
                          size: 16.r,
                        ),
                        SizedBox(width: 5.w),
                        Text(
                          tutorial['views'] as String? ?? '—',
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: AppColors.textLight,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          tutorial['cost'] as String? ?? '—',
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            color: _successGreen,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getDifficultyColor(String difficulty) {
    switch (difficulty) {
      case 'Beginner':
        return _successGreen;
      case 'Intermediate':
        return _ratingYellow;
      case 'Advanced':
        return AppColors.accentOrange;
      default:
        return AppColors.accentCyan;
    }
  }

  Widget _buildUploadButton() {
    return FloatingActionButton.extended(
      onPressed: () {
        Navigator.pushNamed(context, AppRoutes.uploadVideo);
      },
      backgroundColor: AppColors.accentOrange,
      icon: const Icon(Icons.upload),
      label: const Text(
        'Upload',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
