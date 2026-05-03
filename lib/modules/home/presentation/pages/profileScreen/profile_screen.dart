import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_routes.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color _successGreen = Color(0xFF00E676);
  static const Color _ratingYellow = Color(0xFFFFD600);

  final Map<String, dynamic> userProfile = {
    'name': 'John Doe',
    'email': 'john.doe@email.com',
    'phone': '+1 (555) 123-4567',
    'location': 'San Francisco, CA',
    'memberSince': 'January 2024',
    'totalScans': 47,
    'tutorialsWatched': 23,
    'savedCodes': 12,
  };

  final List<Map<String, dynamic>> vehicles = [
    {
      'name': 'Toyota Camry 2020',
      'vin': '4T1B11HK...8901',
      'mileage': '45,230 miles',
      'health': 78,
      'isPrimary': true,
    },
    {
      'name': 'Honda Civic 2018',
      'vin': '2HGFC2F5...3456',
      'mileage': '62,450 miles',
      'health': 82,
      'isPrimary': false,
    },
  ];

  String get _initials {
    final name = userProfile['name'] as String? ?? '';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '?';
    return parts.take(2).map((n) => n.isNotEmpty ? n[0].toUpperCase() : '').join();
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
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20.r),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildProfileCard(),
                      SizedBox(height: 25.h),
                      _buildStatsSection(),
                      SizedBox(height: 25.h),
                      _buildPersonalInfoSection(),
                      SizedBox(height: 25.h),
                      _buildVehiclesSection(),
                      SizedBox(height: 25.h),
                      _buildAchievementsSection(),
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
            icon: Icon(Icons.arrow_back, color: AppColors.accentCyan, size: 24.r),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            'My Profile',
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.share, color: AppColors.accentCyan, size: 24.r),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: EdgeInsets.all(25.r),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.accentCyan.withValues(alpha: 0.1),
            AppColors.accentOrange.withValues(alpha: 0.05),
          ],
        ),
        border: Border.all(
          color: AppColors.accentCyan.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(25.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 100.w,
                height: 100.h,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.accentCyan, AppColors.accentOrange],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accentCyan.withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    _initials,
                    style: TextStyle(
                      fontSize: 36.sp,
                      fontWeight: FontWeight.w900,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 32.w,
                  height: 32.h,
                  decoration: BoxDecoration(
                    color: _successGreen,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.backgroundDark,
                      width: 3,
                    ),
                  ),
                  child: Icon(
                    Icons.verified,
                    color: AppColors.white,
                    size: 18.r,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 20.h),
          Text(
            userProfile['name'] as String? ?? '',
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            userProfile['email'] as String? ?? '',
            style: TextStyle(
              fontSize: 15.sp,
              color: AppColors.textLight.withValues(alpha: 0.7),
            ),
          ),
          SizedBox(height: 20.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, AppRoutes.editProfile);
              },
              icon: const Icon(Icons.edit),
              label: Text(
                'Edit Profile',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentCyan,
                foregroundColor: AppColors.white,
                padding: EdgeInsets.symmetric(vertical: 15.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    return Container(
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: AppColors.white.withValues(alpha: 0.1),
        ),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Column(
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
                'Activity Stats',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textLight,
                ),
              ),
            ],
          ),
          SizedBox(height: 20.h),
          Row(
            children: [
              _buildStatItem(
                '🔍',
                'Total Scans',
                (userProfile['totalScans'] ?? 0).toString(),
              ),
              _buildStatItem(
                '📹',
                'Videos Watched',
                (userProfile['tutorialsWatched'] ?? 0).toString(),
              ),
              _buildStatItem(
                '🔖',
                'Saved Codes',
                (userProfile['savedCodes'] ?? 0).toString(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String icon, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(icon, style: TextStyle(fontSize: 32.sp)),
          SizedBox(height: 8.h),
          Text(
            value,
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.w900,
              color: AppColors.accentCyan,
            ),
          ),
          SizedBox(height: 5.h),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.sp,
              color: AppColors.textLight.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoSection() {
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
              'Personal Information',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        SizedBox(height: 15.h),
        _buildInfoCard('📧', 'Email', userProfile['email'] as String? ?? ''),
        _buildInfoCard('📱', 'Phone', userProfile['phone'] as String? ?? ''),
        _buildInfoCard(
          '📍',
          'Location',
          userProfile['location'] as String? ?? '',
        ),
        _buildInfoCard(
          '📅',
          'Member Since',
          userProfile['memberSince'] as String? ?? '',
        ),
      ],
    );
  }

  Widget _buildInfoCard(String icon, String label, String value) {
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
          Text(icon, style: TextStyle(fontSize: 24.sp)),
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
                    color: AppColors.textLight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehiclesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                  'My Vehicles',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textLight,
                  ),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: () {},
              icon: Icon(Icons.add, color: AppColors.accentCyan, size: 24.r),
              label: Text(
                'Add',
                style: TextStyle(color: AppColors.accentCyan),
              ),
            ),
          ],
        ),
        SizedBox(height: 15.h),
        ...vehicles.map((vehicle) => _buildVehicleCard(vehicle)),
      ],
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> vehicle) {
    final isPrimary = vehicle['isPrimary'] as bool? ?? false;
    final name = vehicle['name'] as String? ?? '';
    final vin = vehicle['vin'] as String? ?? '';
    final mileage = vehicle['mileage'] as String? ?? '';
    final health = vehicle['health'] ?? 0;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(18.r),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: isPrimary
              ? AppColors.accentCyan
              : AppColors.white.withValues(alpha: 0.1),
          width: isPrimary ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(15.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50.w,
                height: 50.h,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.accentCyan, AppColors.accentOrange],
                  ),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(
                  Icons.directions_car,
                  color: AppColors.white,
                  size: 28.r,
                ),
              ),
              SizedBox(width: 15.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textLight,
                            ),
                          ),
                        ),
                        if (isPrimary)
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
                              'Primary',
                              style: TextStyle(
                                fontSize: 10.sp,
                                fontWeight: FontWeight.w700,
                                color: AppColors.accentCyan,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      vin,
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
          SizedBox(height: 15.h),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mileage',
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColors.textLight.withValues(alpha: 0.6),
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      mileage,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textLight,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Health Score',
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColors.textLight.withValues(alpha: 0.6),
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      '$health%',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: _successGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementsSection() {
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
              'Achievements',
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
          height: 100.h,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildAchievementBadge('🏆', 'First Scan', true),
              _buildAchievementBadge('🔧', 'DIY Master', true),
              _buildAchievementBadge('📹', 'Video Learner', true),
              _buildAchievementBadge('⭐', 'Pro User', false),
              _buildAchievementBadge('🚗', 'Fleet Owner', true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAchievementBadge(String icon, String label, bool unlocked) {
    return Container(
      width: 80.w,
      margin: EdgeInsets.only(right: 12.w),
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: unlocked
            ? _ratingYellow.withValues(alpha: 0.1)
            : AppColors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: unlocked
              ? _ratingYellow
              : AppColors.white.withValues(alpha: 0.1),
        ),
        borderRadius: BorderRadius.circular(15.r),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Opacity(
            opacity: unlocked ? 1.0 : 0.3,
            child: Text(icon, style: TextStyle(fontSize: 32.sp)),
          ),
          SizedBox(height: 8.h),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.sp,
              fontWeight: FontWeight.w600,
              color: unlocked
                  ? _ratingYellow
                  : AppColors.textLight.withValues(alpha: 0.5),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
