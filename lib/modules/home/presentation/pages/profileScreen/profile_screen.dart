import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/app_services.dart';
import '../../../../../core/core.dart';
import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/services/dtc_history_service.dart';
import 'profile_avatar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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
  String _orNotSet(String? value) => value == null || value.trim().isEmpty
      ? context.tr('profile_not_set')
      : value;

  Future<void> _openEditProfile() async {
    await Navigator.pushNamed(context, AppRoutes.editProfile);
    // Pick up edits saved on the edit screen.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(title: context.tr('my_profile')),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsetsDirectional.fromSTEB(
                  AppSizes.space20.w,
                  AppSizes.space8.h,
                  AppSizes.space20.w,
                  AppSizes.space24.h,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSizes.space24.h,
                  children: [
                    _buildProfileCard(),
                    _buildStatsSection(),
                    _buildPersonalInfoSection(),
                    _buildVehiclesSection(),
                    _buildAchievementsSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Avatar, name and email, with the "Edit profile" action underneath.
  Widget _buildProfileCard() {
    final p = context.colors;
    final hasName = _session.name?.trim().isNotEmpty == true;
    final hasEmail = _session.email?.trim().isNotEmpty == true;
    // No "verified" badge: nothing in the app or backend verifies an account.
    return AppCard(
      padding: EdgeInsets.all(AppSizes.space16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProfileAvatar(size: 64.r),
              SizedBox(width: AppSizes.space16.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasName ? _session.name! : context.tr('profile_guest'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.title.copyWith(color: p.text),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      hasEmail
                          ? _session.email!
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
            ],
          ),
          SizedBox(height: AppSizes.space16.h),
          AppButton.secondary(
            label: context.tr('edit_profile'),
            icon: Icons.edit_outlined,
            compact: true,
            onPressed: _openEditProfile,
          ),
        ],
      ),
    );
  }

  /// A titled block: [SectionTitle] followed by [child].
  Widget _section(String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [SectionTitle(title), child],
    );
  }

  Widget _buildStatsSection() {
    // Three across leaves no room for an icon beside the label (it cut
    // "Videos watched" short, worse in Arabic), so these tiles go without.
    Widget stat(String labelKey, String value) => Expanded(
      child: StatTile(label: context.tr(labelKey), value: value),
    );

    return _section(
      context.tr('activity_stats'),
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSizes.space12.w,
          children: [
            stat('total_scans', _totalScans?.toString() ?? '—'),
            // Not tracked anywhere in the app yet.
            stat('videos_watched', '—'),
            // There is no "save code" feature yet.
            stat('saved_codes', '—'),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalInfoSection() {
    return SettingsGroup(
      title: context.tr('personal_information'),
      children: [
        _infoRow(
          Icons.mail_outline_rounded,
          context.tr('email'),
          _orNotSet(_session.email),
        ),
        _infoRow(
          Icons.phone_outlined,
          context.tr('phone_short'),
          _orNotSet(_session.phone),
        ),
        _infoRow(
          Icons.location_on_outlined,
          context.tr('location_label'),
          _orNotSet(_session.location),
        ),
        // The login response carries no account creation date.
        _infoRow(
          Icons.calendar_today_outlined,
          context.tr('member_since'),
          context.tr('profile_not_available'),
        ),
      ],
    );
  }

  /// Read-only row: [label] with its [value] underneath.
  Widget _infoRow(IconData icon, String label, String value) {
    return MergeSemantics(
      child: SettingsTile(
        leading: IconBox.neutral(icon),
        title: label,
        subtitle: value,
      ),
    );
  }

  /// No vehicle garage exists in the app (nothing stores the user's cars),
  /// so this explains where vehicle data comes from instead of listing
  /// placeholder cars.
  Widget _buildVehiclesSection() {
    return SettingsGroup(
      title: context.tr('my_vehicles'),
      children: [
        SettingsTile(
          leading: const IconBox.neutral(Icons.directions_car_outlined),
          title: context.tr('profile_no_vehicles'),
        ),
      ],
    );
  }

  Widget _buildAchievementsSection() {
    final badges = [
      // Only "first scan" has real data behind it (scan history); the others
      // stay locked until the app tracks them.
      (
        Icons.emoji_events_outlined,
        context.tr('ach_first_scan'),
        (_totalScans ?? 0) > 0,
      ),
      (Icons.build_outlined, context.tr('ach_diy_master'), false),
      (
        Icons.play_circle_outline_rounded,
        context.tr('ach_video_learner'),
        false,
      ),
      (Icons.star_outline_rounded, context.tr('ach_pro_user'), false),
      (Icons.directions_car_outlined, context.tr('ach_fleet_owner'), false),
    ];
    const perRow = 3;
    final gap = AppSizes.space8.w;
    return _section(
      context.tr('achievements'),
      AppCard(
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.space8.w,
          vertical: AppSizes.space16.h,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
            return Wrap(
              spacing: gap,
              runSpacing: AppSizes.space16.h,
              children: [
                for (final (icon, label, unlocked) in badges)
                  SizedBox(
                    width: width,
                    child: _buildAchievementBadge(icon, label, unlocked),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAchievementBadge(IconData icon, String label, bool unlocked) {
    final p = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Locked badges are dimmed; the unlocked one is drawn fully opaque.
        Opacity(
          opacity: unlocked ? 1.0 : 0.45,
          child: unlocked
              ? IconBox(icon, size: 44)
              : IconBox.neutral(icon, size: 44),
        ),
        SizedBox(height: AppSizes.space8.h),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.label.copyWith(
            color: unlocked ? p.text : p.muted,
          ),
        ),
      ],
    );
  }
}
