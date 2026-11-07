import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/app_services.dart';
import '../../../../../core/bloc/locale/locale_bloc.dart';
import '../../../../../core/bloc/locale/locale_event.dart';
import '../../../../../core/core.dart';
import '../../../../../core/localization/app_localizations.dart';
import '../profileScreen/profile_avatar.dart';
import 'app_settings_store.dart';
import 'dash_cam_settings_screen.dart';

/// The Profile tab root: account card, grouped preferences and Log out.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Defaults until [_loadSettings] resolves; every change is persisted via
  // [AppSettingsStore]. Note: none of these is read by another feature yet
  // (AlertService always plays sound). The app theme lives in
  // [AppServices.theme], driven by the Appearance control.
  bool notifications = const AppSettings().notifications;
  bool autoScan = const AppSettings().autoScan;
  bool soundEffects = const AppSettings().soundEffects;
  String units = const AppSettings().units;

  static const String _appVersion = '1.0.0';

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
      soundEffects = s.soundEffects;
      units = s.units;
    });
  }

  void _setToggle(String key, bool value, void Function(bool) apply) {
    setState(() => apply(value));
    _store.setBool(key, value);
  }

  /// Reflects the active app locale (not a stale local default).
  String get language => Localizations.localeOf(context).languageCode == 'ar'
      ? 'العربية'
      : 'English';

  /// Honest feedback for rows with nothing behind them yet.
  void _showSnack(String key) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.tr(key))));
  }

  void _onLanguageChanged(String value) {
    final locale = value == 'العربية' ? const Locale('ar') : const Locale('en');
    context.read<LocaleBloc>().add(ChangeLocale(locale));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(title: context.tr('settings_title')),
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
                    _buildProfileCard(),
                    _buildGeneralSettings(),
                    _buildPreferencesSettings(),
                    _buildAboutSection(),
                    AppButton.danger(
                      label: context.tr('logout'),
                      icon: Icons.logout_rounded,
                      onPressed: _showLogoutDialog,
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

  Widget _buildProfileCard() {
    final p = context.colors;
    final session = AppServices.instance.session;
    return AppCard(
      onTap: () => Navigator.pushNamed(context, AppRoutes.profile),
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSizes.space16.w,
        14.h,
        AppSizes.space12.w,
        14.h,
      ),
      child: Row(
        children: [
          ProfileAvatar(size: 48.r),
          SizedBox(width: AppSizes.space12.w),
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
                  style: AppTextStyles.title.copyWith(color: p.text),
                ),
                SizedBox(height: 2.h),
                Text(
                  session.email?.trim().isNotEmpty == true
                      ? session.email!
                      : context.tr('profile_not_signed_in'),
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
          Icon(Icons.chevron_right_rounded, color: p.muted, size: 22.r),
        ],
      ),
    );
  }

  Widget _buildGeneralSettings() {
    return SettingsGroup(
      title: context.tr('general'),
      children: [
        SettingsTile.toggle(
          leading: const IconBox.neutral(Icons.notifications_none_rounded),
          title: context.tr('notifications'),
          value: notifications,
          onChanged: (v) => _setToggle(
            AppSettingsStore.notificationsKey,
            v,
            (v) => notifications = v,
          ),
        ),
        SettingsTile.toggle(
          leading: const IconBox.neutral(Icons.bluetooth_searching_rounded),
          title: context.tr('auto_scan'),
          value: autoScan,
          onChanged: (v) =>
              _setToggle(AppSettingsStore.autoScanKey, v, (v) => autoScan = v),
        ),
        SettingsTile.toggle(
          leading: const IconBox.neutral(Icons.volume_up_outlined),
          title: context.tr('sound_effects'),
          value: soundEffects,
          onChanged: (v) => _setToggle(
            AppSettingsStore.soundEffectsKey,
            v,
            (v) => soundEffects = v,
          ),
        ),
        _buildAppearanceRow(),
      ],
    );
  }

  /// Light / Dark / System. Writes [AppServices.theme], which `MaterialApp`
  /// listens to, so the whole app restyles at once; the choice is persisted.
  Widget _buildAppearanceRow() {
    final theme = AppServices.instance.theme;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.space16.w,
        vertical: AppSizes.space12.h,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBox.neutral(Icons.dark_mode_outlined),
              SizedBox(width: AppSizes.space12.w),
              Expanded(
                child: Text(
                  context.tr('appearance'),
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w500,
                    color: context.colors.text,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: AppSizes.space12.h),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: theme,
            builder: (context, mode, _) => AppSegmentedControl<ThemeMode>(
              key: const Key('appearance_control'),
              segments: [
                (ThemeMode.light, context.tr('theme_light')),
                (ThemeMode.dark, context.tr('theme_dark')),
                (ThemeMode.system, context.tr('theme_system')),
              ],
              value: mode,
              onChanged: theme.set,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesSettings() {
    return SettingsGroup(
      title: context.tr('preferences'),
      children: [
        SettingsTile(
          leading: const IconBox.neutral(Icons.language_rounded),
          title: context.tr('language'),
          value: language,
          onTap: () => _showSelectorDialog(
            context.tr('language'),
            language,
            const ['English', 'العربية'],
            _onLanguageChanged,
          ),
        ),
        SettingsTile(
          leading: const IconBox.neutral(Icons.straighten_rounded),
          title: context.tr('units'),
          value: _unitsLabel(units),
          onTap: () => _showSelectorDialog(
            context.tr('units'),
            units,
            const ['Metric', 'Imperial'],
            (v) {
              setState(() => units = v);
              _store.setUnits(v);
            },
            _unitsLabel,
          ),
        ),
        SettingsTile(
          leading: const IconBox.neutral(Icons.videocam_outlined),
          title: context.tr('dash_cam'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DashCamSettingsScreen()),
          ),
        ),
        SettingsTile(
          leading: const IconBox.neutral(Icons.manage_search_rounded),
          title: context.tr('dtc_lookup'),
          onTap: () => Navigator.pushNamed(context, AppRoutes.dtcLookup),
        ),
        SettingsTile(
          leading: const IconBox.neutral(Icons.directions_car_outlined),
          title: context.tr('vehicle_profile'),
          // No vehicle garage exists yet (nothing stores the user's cars).
          onTap: () => _showSnack('vehicle_profile_unavailable'),
        ),
        SettingsTile(
          leading: const IconBox.neutral(Icons.shield_outlined),
          title: context.tr('data_privacy'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const _DataPrivacyPage()),
          ),
        ),
      ],
    );
  }

  String _unitsLabel(String v) =>
      context.tr(v == 'Imperial' ? 'units_imperial' : 'units_metric');

  Widget _buildAboutSection() {
    return SettingsGroup(
      title: context.tr('about'),
      children: [
        // Informational only: no tap target, so no chevron.
        SettingsTile(
          leading: const IconBox.neutral(Icons.info_outline_rounded),
          title: context.tr('app_version'),
          value: _appVersion,
        ),
        SettingsTile(
          leading: const IconBox.neutral(Icons.description_outlined),
          title: context.tr('terms_of_service'),
          onTap: () => _showSnack('terms_unavailable'),
        ),
        SettingsTile(
          leading: const IconBox.neutral(Icons.lock_outline_rounded),
          title: context.tr('privacy_policy'),
          onTap: () => _showSnack('privacy_policy_unavailable'),
        ),
        SettingsTile(
          leading: const IconBox.neutral(Icons.support_agent_rounded),
          title: context.tr('support'),
          // No support channel (email, URL, chat) is configured in the app.
          onTap: () => _showSnack('support_unavailable'),
        ),
      ],
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
        title: Text('${context.tr('select')} $title'),
        contentPadding: EdgeInsets.symmetric(vertical: AppSizes.space12.h),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((option) {
            return ListTile(
              contentPadding: EdgeInsets.symmetric(
                horizontal: AppSizes.space24.w,
              ),
              title: Text(labelOf?.call(option) ?? option),
              trailing: option == currentValue
                  ? Icon(Icons.check, color: context.colors.primary)
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
        title: Text(ctx.tr('logout_confirm')),
        content: Text(ctx.tr('logout_confirm_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.tr('cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _logout();
            },
            style: TextButton.styleFrom(foregroundColor: ctx.colors.crit),
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
    (Icons.lock_outline_rounded, 'dp_secure_title', 'dp_secure_body'),
    (Icons.smartphone_rounded, 'dp_local_title', 'dp_local_body'),
    (Icons.cloud_outlined, 'dp_server_title', 'dp_server_body'),
    (Icons.travel_explore_rounded, 'dp_lookup_title', 'dp_lookup_body'),
    (Icons.logout_rounded, 'dp_signout_title', 'dp_signout_body'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(title: context.tr('data_privacy')),
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
                  spacing: AppSizes.space16.h,
                  children: [
                    Text(
                      context.tr('dp_intro'),
                      style: AppTextStyles.body.copyWith(color: p.text2),
                    ),
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < _sections.length; i++) ...[
                            if (i > 0)
                              Divider(height: 1, thickness: 1, color: p.border),
                            _buildSection(context, _sections[i]),
                          ],
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
    );
  }

  Widget _buildSection(
    BuildContext context,
    (IconData, String, String) section,
  ) {
    final (icon, titleKey, bodyKey) = section;
    final p = context.colors;
    return Padding(
      padding: EdgeInsets.all(AppSizes.space16.r),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBox.neutral(icon),
          SizedBox(width: AppSizes.space12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(titleKey),
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
                SizedBox(height: AppSizes.space4.h),
                Text(
                  context.tr(bodyKey),
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
}
