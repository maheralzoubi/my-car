import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/app_services.dart';
import '../../../../../core/bloc/locale/locale_bloc.dart';
import '../../../../../core/bloc/locale/locale_event.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_routes.dart';
import '../../../../../core/localization/app_localizations.dart';
import '../profileScreen/profile_avatar.dart';
import 'app_settings_store.dart';
import 'dash_cam_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Defaults until [_loadSettings] resolves; every change is persisted via
  // [AppSettingsStore]. Note: none of these is read by another feature yet
  // (the app theme is fixed to dark and AlertService always plays sound).
  bool notifications = const AppSettings().notifications;
  bool autoScan = const AppSettings().autoScan;
  bool darkMode = const AppSettings().darkMode;
  bool soundEffects = const AppSettings().soundEffects;
  String units = const AppSettings().units;

  AppSettingsStore get _store => AppServices.instance.settings;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await _store.load();
    if (!mounted) return;
    setState(() {
      notifications = s.notifications;
      autoScan = s.autoScan;
      darkMode = s.darkMode;
      soundEffects = s.soundEffects;
      units = s.units;
    });
  }

  void _setToggle(String key, bool value, void Function(bool) apply) {
    setState(() => apply(value));
    _store.setBool(key, value);
  }

  /// Reflects the active app locale (not a stale local default).
  String get language =>
      Localizations.localeOf(context).languageCode == 'ar' ? 'العربية' : 'English';

  static const Color _dangerRed = Color(0xFFFF1744);
  static const Color _successGreen = Color(0xFF00E676);
  static const Color _successGreenDark = Color(0xFF00C853);

  /// Honest feedback for rows with nothing behind them yet.
  void _showSnack(String key) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.tr(key))));
  }

  void _onLanguageChanged(String value) {
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
    final session = AppServices.instance.session;
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
              child: ProfileAvatarContent(fontSize: 24.sp),
            ),
            SizedBox(width: 20.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.name?.trim().isNotEmpty == true
                        ? session.name!
                        : context.tr('profile_guest'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textLight,
                    ),
                  ),
                  SizedBox(height: 5.h),
                  Text(
                    session.email?.trim().isNotEmpty == true
                        ? session.email!
                        : context.tr('profile_not_signed_in'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
          (v) => _setToggle(
            AppSettingsStore.notificationsKey,
            v,
            (v) => notifications = v,
          ),
        ),
        _buildSettingToggle(
          '🔄',
          context.tr('auto_scan'),
          context.tr('auto_scan_sub'),
          autoScan,
          (v) => _setToggle(AppSettingsStore.autoScanKey, v, (v) => autoScan = v),
        ),
        _buildSettingToggle(
          '🌙',
          context.tr('dark_mode'),
          context.tr('dark_mode_sub'),
          darkMode,
          (v) => _setToggle(AppSettingsStore.darkModeKey, v, (v) => darkMode = v),
        ),
        _buildSettingToggle(
          '🔊',
          context.tr('sound_effects'),
          context.tr('sound_effects_sub'),
          soundEffects,
          (v) => _setToggle(
            AppSettingsStore.soundEffectsKey,
            v,
            (v) => soundEffects = v,
          ),
        ),
        _buildSettingItem(
          '📹',
          context.tr('dash_cam'),
          context.tr('dash_cam_settings_sub'),
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DashCamSettingsScreen()),
          ),
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
          (v) {
            setState(() => units = v);
            _store.setUnits(v);
          },
          (v) => context.tr(v == 'Imperial' ? 'units_imperial' : 'units_metric'),
        ),
        _buildSettingItem(
          '🚗',
          context.tr('vehicle_profile'),
          context.tr('vehicle_profile_sub'),
          // No vehicle garage exists yet (nothing stores the user's cars).
          () => _showSnack('vehicle_profile_unavailable'),
        ),
        _buildSettingItem(
          '📊',
          context.tr('data_privacy'),
          context.tr('data_privacy_sub'),
          () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const _DataPrivacyPage()),
          ),
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
          () => _showSnack('terms_unavailable'),
        ),
        _buildSettingItem(
          '🔒',
          context.tr('privacy_policy'),
          context.tr('privacy_sub'),
          () => _showSnack('privacy_policy_unavailable'),
        ),
        _buildSettingItem(
          '💬',
          context.tr('support'),
          context.tr('support_sub'),
          // No support channel (email, URL, chat) is configured in the app.
          () => _showSnack('support_unavailable'),
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
    void Function(String) onChanged, [
    String Function(String)? labelOf,
  ]) {
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
                _showSelectorDialog(title, currentValue, options, onChanged, labelOf),
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
                    labelOf?.call(currentValue) ?? currentValue,
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
          alignment: value
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
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
    void Function(String) onChanged, [
    String Function(String)? labelOf,
  ]) {
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
                labelOf?.call(option) ?? option,
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

  /// Clears the session (socket, token, cached profile, per-account prefs)
  /// and returns to the auth screen with nothing left to go "back" to.
  Future<void> _logout() async {
    final navigator = Navigator.of(context);
    try {
      await AppServices.instance.logout();
    } catch (_) {
      // The in-memory token is already gone (Session.clear drops it before
      // touching storage), so leaving is still correct.
    }
    navigator.pushNamedAndRemoveUntil(AppRoutes.auth, (_) => false);
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
            onPressed: () {
              Navigator.pop(ctx);
              _logout();
            },
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

/// A plain summary of what this version of the app keeps on the device and
/// what it sends off it — derived from the code (Session, AppSettingsStore,
/// DtcHistoryService, MaintenanceService, ProfilePhotoStore, DtcRepository,
/// the auth and roadside repositories). Keep it in sync when that changes.
class _DataPrivacyPage extends StatelessWidget {
  const _DataPrivacyPage();

  static const _sections = [
    ('🔐', 'dp_secure_title', 'dp_secure_body'),
    ('📱', 'dp_local_title', 'dp_local_body'),
    ('☁️', 'dp_server_title', 'dp_server_body'),
    ('🌐', 'dp_lookup_title', 'dp_lookup_body'),
    ('🚪', 'dp_signout_title', 'dp_signout_body'),
  ];

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
              Padding(
                padding: EdgeInsets.all(20.r),
                child: Row(
                  children: [
                    const BackButton(color: AppColors.accentCyan),
                    Expanded(
                      child: Text(
                        context.tr('data_privacy'),
                        style: TextStyle(
                          fontSize: 24.sp,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textLight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 20.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('dp_intro'),
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: AppColors.textLight.withValues(alpha: 0.7),
                        ),
                      ),
                      SizedBox(height: 15.h),
                      for (final (icon, title, body) in _sections)
                        _buildSection(context, icon, title, body),
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

  Widget _buildSection(
    BuildContext context,
    String icon,
    String titleKey,
    String bodyKey,
  ) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(18.r),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(15.r),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: TextStyle(fontSize: 24.sp)),
          SizedBox(width: 15.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(titleKey),
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textLight,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  context.tr(bodyKey),
                  style: TextStyle(
                    fontSize: 13.sp,
                    height: 1.4,
                    color: AppColors.textLight.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
