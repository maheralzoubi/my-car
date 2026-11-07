import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/app_services.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_routes.dart';
import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/services/dtc_history_service.dart';
import 'profile_avatar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color _ratingYellow = Color(0xFFFFD600);

  // Only what the app actually knows is shown: the session user (the
  // backend has no profile endpoint beyond login/register), this device's
  // scan history, and nothing invented for the rest.
  final _session = AppServices.instance.session;
  int? _totalScans;

  @override
  void initState() {
    super.initState();
    _loadScanCount();
  }

  Future<void> _loadScanCount() async {
    try {
      await DtcHistoryService.instance.load();
    } catch (_) {
      // No stored history (or storage unavailable): count what is in memory.
    }
    if (!mounted) return;
    setState(() => _totalScans = DtcHistoryService.instance.entries.length);
  }

  /// [value], or a localized "not set" when empty.
  String _orNotSet(String? value) =>
      value == null || value.trim().isEmpty ? context.tr('profile_not_set') : value;

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
            context.tr('my_profile'),
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
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
          // No "verified" badge: nothing in the app or backend verifies an
          // account.
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
            child: ProfileAvatarContent(fontSize: 36.sp),
          ),
          SizedBox(height: 20.h),
          Text(
            _session.name?.trim().isNotEmpty == true
                ? _session.name!
                : context.tr('profile_guest'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
          SizedBox(height: 20.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                await Navigator.pushNamed(context, AppRoutes.editProfile);
                // Pick up edits saved on the edit screen.
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.edit),
              label: Text(
                context.tr('edit_profile'),
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
                context.tr('activity_stats'),
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
                context.tr('total_scans'),
                _totalScans?.toString() ?? '—',
              ),
              _buildStatItem(
                '📹',
                context.tr('videos_watched'),
                // Not tracked anywhere in the app yet.
                '—',
              ),
              _buildStatItem(
                '🔖',
                context.tr('saved_codes'),
                // There is no "save code" feature yet.
                '—',
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
              context.tr('personal_information'),
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        SizedBox(height: 15.h),
        _buildInfoCard('📧', context.tr('email'), _orNotSet(_session.email)),
        _buildInfoCard('📱', context.tr('phone_short'), _orNotSet(_session.phone)),
        _buildInfoCard(
          '📍',
          context.tr('location_label'),
          _orNotSet(_session.location),
        ),
        // The login response carries no account creation date.
        _buildInfoCard(
          '📅',
          context.tr('member_since'),
          context.tr('profile_not_available'),
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

  /// No vehicle garage exists in the app (nothing stores the user's cars),
  /// so this explains where vehicle data comes from instead of listing
  /// placeholder cars.
  Widget _buildVehiclesSection() {
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
              context.tr('my_vehicles'),
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        SizedBox(height: 15.h),
        Container(
          width: double.infinity,
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
              Icon(
                Icons.directions_car,
                color: AppColors.accentCyan.withValues(alpha: 0.7),
                size: 28.r,
              ),
              SizedBox(width: 15.w),
              Expanded(
                child: Text(
                  context.tr('profile_no_vehicles'),
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColors.textLight.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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
              context.tr('achievements'),
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        SizedBox(height: 15.h),
        // Tall enough for the emoji + a two-line label at any text scale the
        // design size produces (was 100.h: overflowed by 8 px EN / 14 px AR).
        SizedBox(
          height: 112.h,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // Only "first scan" has real data behind it (scan history);
              // the others stay locked until the app tracks them.
              _buildAchievementBadge(
                '🏆',
                context.tr('ach_first_scan'),
                (_totalScans ?? 0) > 0,
              ),
              _buildAchievementBadge('🔧', context.tr('ach_diy_master'), false),
              _buildAchievementBadge('📹', context.tr('ach_video_learner'), false),
              _buildAchievementBadge('⭐', context.tr('ach_pro_user'), false),
              _buildAchievementBadge('🚗', context.tr('ach_fleet_owner'), false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAchievementBadge(String icon, String label, bool unlocked) {
    return Container(
      width: 80.w,
      margin: EdgeInsetsDirectional.only(end: 12.w),
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 10.h),
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
            child: Text(icon, style: TextStyle(fontSize: 28.sp)),
          ),
          SizedBox(height: 6.h),
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
