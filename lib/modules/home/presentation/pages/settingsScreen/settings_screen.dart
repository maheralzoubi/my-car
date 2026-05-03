import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/bloc/locale/locale_bloc.dart';
import '../../../../../core/bloc/locale/locale_event.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_routes.dart';
import '../../../../../core/localization/app_localizations.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool notifications = true;
  bool autoScan = false;
  bool darkMode = true;
  bool soundEffects = true;
  bool dashCam = true;
  String language = 'English';
  String units = 'Metric';

  static const Color _dangerRed = Color(0xFFFF1744);
  static const Color _successGreen = Color(0xFF00E676);
  static const Color _successGreenDark = Color(0xFF00C853);

  void _onLanguageChanged(String value) {
    setState(() => language = value);
    final locale =
        value == 'العربية' ? const Locale('ar') : const Locale('en');
    context.read<LocaleBloc>().add(ChangeLocale(locale));
  }

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
                      _buildProfileSection(),
                      SizedBox(height: 30.h),
                      _buildGeneralSettings(),
                      SizedBox(height: 30.h),
                      _buildPreferencesSettings(),
                      SizedBox(height: 30.h),
                      _buildAboutSection(),
                      SizedBox(height: 30.h),
                      _buildDangerZone(),
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
            context.tr('settings_title'),
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

  Widget _buildProfileSection() {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.profile),
      child: Container(
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
        ),
        child: Row(
          children: [
            Container(
              width: 70.w,
              height: 70.h,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.accentCyan, AppColors.accentOrange],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accentCyan.withValues(alpha: 0.3),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  'JD',
                  style: TextStyle(
                    fontSize: 24.sp,
                    fontWeight: FontWeight.w900,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
            SizedBox(width: 20.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'John Doe',
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textLight,
                    ),
                  ),
                  SizedBox(height: 5.h),
                  Text(
                    'john.doe@email.com',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColors.textLight.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: AppColors.accentCyan),
              onPressed: () =>
                  Navigator.pushNamed(context, AppRoutes.profile),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context.tr('general')),
        _buildSettingToggle(
          '🔔',
          context.tr('notifications'),
          context.tr('notifications_sub'),
          notifications,
          (v) => setState(() => notifications = v),
        ),
        _buildSettingToggle(
          '🔄',
          context.tr('auto_scan'),
          context.tr('auto_scan_sub'),
          autoScan,
          (v) => setState(() => autoScan = v),
        ),
        _buildSettingToggle(
          '🌙',
          context.tr('dark_mode'),
          context.tr('dark_mode_sub'),
          darkMode,
          (v) => setState(() => darkMode = v),
        ),
        _buildSettingToggle(
          '🔊',
          context.tr('sound_effects'),
          context.tr('sound_effects_sub'),
          soundEffects,
          (v) => setState(() => soundEffects = v),
        ),
        _buildSettingToggle(
          '📹',
          context.tr('dash_cam'),
          context.tr('dash_cam_sub'),
          dashCam,
          (v) => setState(() => dashCam = v),
        ),
        _buildSettingItem(
          '🔎',
          context.tr('dtc_lookup'),
          context.tr('dtc_lookup_sub'),
          () => Navigator.pushNamed(context, AppRoutes.dtcLookup),
        ),
      ],
    );
  }

  Widget _buildPreferencesSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context.tr('preferences')),
        _buildSettingSelector(
          '🌐',
          context.tr('language'),
          language,
          ['English', 'العربية'],
          _onLanguageChanged,
        ),
        _buildSettingSelector(
          '📏',
          context.tr('units'),
          units,
          ['Metric', 'Imperial'],
          (v) => setState(() => units = v),
        ),
        _buildSettingItem(
          '🚗',
          context.tr('vehicle_profile'),
          context.tr('vehicle_profile_sub'),
          () {},
        ),
        _buildSettingItem(
          '📊',
          context.tr('data_privacy'),
          context.tr('data_privacy_sub'),
          () {},
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context.tr('about')),
        _buildSettingItem('ℹ️', context.tr('app_version'), 'v1.0.0', () {}),
        _buildSettingItem(
          '📄',
          context.tr('terms_of_service'),
          context.tr('terms_sub'),
          () {},
        ),
        _buildSettingItem(
          '🔒',
          context.tr('privacy_policy'),
          context.tr('privacy_sub'),
          () {},
        ),
        _buildSettingItem(
          '💬',
          context.tr('support'),
          context.tr('support_sub'),
          () {},
        ),
      ],
    );
  }

  Widget _buildDangerZone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context.tr('danger_zone')),
        GestureDetector(
          onTap: _showLogoutDialog,
          child: Container(
            padding: EdgeInsets.all(18.r),
            decoration: BoxDecoration(
              color: _dangerRed.withValues(alpha: 0.1),
              border: Border.all(color: _dangerRed.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(15.r),
            ),
            child: Row(
              children: [
                Icon(Icons.logout, color: _dangerRed, size: 24.r),
                SizedBox(width: 15.w),
                Expanded(
                  child: Text(
                    context.tr('logout'),
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: _dangerRed,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: _dangerRed,
                  size: 16.r,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: 15.h),
      child: Row(
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
            title,
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingToggle(
    String icon,
    String title,
    String subtitle,
    bool value,
    void Function(bool) onChanged,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(18.r),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.1)),
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
                  title,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textLight,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColors.textLight.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          _buildToggleSwitch(value, onChanged),
        ],
      ),
    );
  }

  Widget _buildSettingSelector(
    String icon,
    String title,
    String currentValue,
    List<String> options,
    void Function(String) onChanged,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(18.r),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(15.r),
      ),
      child: Row(
        children: [
          Text(icon, style: TextStyle(fontSize: 24.sp)),
          SizedBox(width: 15.w),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.textLight,
              ),
            ),
          ),
          GestureDetector(
            onTap: () =>
                _showSelectorDialog(title, currentValue, options, onChanged),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: AppColors.accentCyan.withValues(alpha: 0.1),
                border: Border.all(
                  color: AppColors.accentCyan.withValues(alpha: 0.3),
                ),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentValue,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accentCyan,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Icon(
                    Icons.arrow_drop_down,
                    color: AppColors.accentCyan,
                    size: 20.r,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem(
    String icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.all(18.r),
        decoration: BoxDecoration(
          color: AppColors.white.withValues(alpha: 0.05),
          border: Border.all(color: AppColors.white.withValues(alpha: 0.1)),
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
                    title,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textLight,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColors.textLight.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: AppColors.accentCyan,
              size: 16.r,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleSwitch(bool value, void Function(bool) onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 60.w,
        height: 32.h,
        decoration: BoxDecoration(
          gradient: value
              ? const LinearGradient(
                  colors: [_successGreen, _successGreenDark],
                )
              : null,
          color: value ? null : AppColors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 28.w,
            height: 28.h,
            margin: EdgeInsets.all(2.r),
            decoration: const BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
            ),
          ),
        ),
      ),
    );
  }

  void _showSelectorDialog(
    String title,
    String currentValue,
    List<String> options,
    void Function(String) onChanged,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        title: Text(
          '${context.tr('select')} $title',
          style: const TextStyle(color: AppColors.textLight),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((option) {
            return ListTile(
              title: Text(
                option,
                style: const TextStyle(color: AppColors.textLight),
              ),
              trailing: option == currentValue
                  ? const Icon(Icons.check, color: AppColors.accentCyan)
                  : null,
              onTap: () {
                onChanged(option);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        title: Text(
          ctx.tr('logout_confirm'),
          style: const TextStyle(color: AppColors.textLight),
        ),
        content: Text(
          ctx.tr('logout_confirm_msg'),
          style: const TextStyle(color: AppColors.textLight),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              ctx.tr('cancel'),
              style: const TextStyle(color: AppColors.accentCyan),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: _dangerRed,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.r),
              ),
            ),
            child: Text(ctx.tr('logout')),
          ),
        ],
      ),
    );
  }
}
