import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/core.dart';
import '../../../../../core/localization/app_localizations.dart';

/// Remote lock / unlock / engine controls.
///
/// No remote-key link exists (OBD-II cannot lock doors or start the engine,
/// and there is no BLE key integration), so the controls only change local
/// state. The header says "Demo" instead of claiming "Connected".
class SmartKeyScreen extends StatefulWidget {
  const SmartKeyScreen({super.key});

  @override
  State<SmartKeyScreen> createState() => _SmartKeyScreenState();
}

class _SmartKeyScreenState extends State<SmartKeyScreen> {
  bool isLocked = true;
  bool engineRunning = false;

  void _lock() => setState(() {
    isLocked = true;
    engineRunning = false;
  });

  void _unlock() => setState(() => isLocked = false);

  /// The engine can only be started once the car is unlocked.
  void _toggleEngine() {
    if (isLocked) return;
    setState(() => engineRunning = !engineRunning);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: context.tr('smart_key_title'),
              actions: [
                StatusBadge(
                  label: context.tr('smart_key_demo'),
                  level: StatusLevel.neutral,
                ),
              ],
            ),
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
                  children: [
                    _buildStatusCard(),
                    SizedBox(height: AppSizes.space24.h),
                    SectionTitle(context.tr('smart_key_controls')),
                    _ControlCard(
                      icon: Icons.lock_rounded,
                      label: context.tr('lock'),
                      active: isLocked,
                      onTap: _lock,
                    ),
                    SizedBox(height: AppSizes.space12.h),
                    _ControlCard(
                      icon: Icons.lock_open_rounded,
                      label: context.tr('unlock'),
                      active: !isLocked,
                      onTap: _unlock,
                    ),
                    SizedBox(height: AppSizes.space12.h),
                    _ControlCard(
                      icon: Icons.power_settings_new_rounded,
                      label: engineRunning
                          ? context.tr('stop_engine')
                          : context.tr('start_engine'),
                      active: engineRunning,
                      hint: isLocked
                          ? context.tr('smart_key_unlock_first')
                          : null,
                      dimmed: isLocked,
                      onTap: _toggleEngine,
                    ),
                    SizedBox(height: AppSizes.space24.h),
                    SettingsGroup(
                      title: context.tr('quick_actions'),
                      children: [
                        SettingsTile(
                          leading: const IconBox.neutral(
                            Icons.ac_unit_rounded,
                          ),
                          title: context.tr('climate'),
                          onTap: _showUnavailable,
                        ),
                        SettingsTile(
                          leading: const IconBox.neutral(
                            Icons.local_parking_rounded,
                          ),
                          title: context.tr('find_car'),
                          onTap: _showUnavailable,
                        ),
                      ],
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

  /// Car tile, lock + engine state, and a note that this is a simulation.
  Widget _buildStatusCard() {
    final p = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBox(Icons.directions_car_filled_rounded, size: 48),
              SizedBox(width: AppSizes.space12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('vehicle_status'),
                      style: AppTextStyles.label.copyWith(color: p.text2),
                    ),
                    SizedBox(height: AppSizes.space8.h),
                    Wrap(
                      spacing: AppSizes.space8.w,
                      runSpacing: AppSizes.space8.h,
                      children: [
                        StatusBadge(
                          label: context.tr(isLocked ? 'locked' : 'unlocked'),
                          level: StatusLevel.neutral,
                          icon: isLocked
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded,
                        ),
                        StatusBadge(
                          label: context.tr(
                            engineRunning ? 'engine_on' : 'engine_off',
                          ),
                          level: engineRunning
                              ? StatusLevel.ok
                              : StatusLevel.neutral,
                          icon: engineRunning
                              ? Icons.power_settings_new_rounded
                              : Icons.power_off_rounded,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: AppSizes.space12.h),
          Divider(height: 1, color: p.border),
          SizedBox(height: AppSizes.space12.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 18.r, color: p.muted),
              SizedBox(width: AppSizes.space8.w),
              Expanded(
                child: Text(
                  context.tr('smart_key_demo_hint'),
                  style: AppTextStyles.label.copyWith(
                    fontWeight: FontWeight.w400,
                    color: p.text2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The screen is a demo with no link to a vehicle, so these actions say so
  /// instead of doing nothing.
  void _showUnavailable() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(context.tr('smart_key_action_unavailable'))),
      );
  }
}

/// A large lock / unlock / engine control. The active one is outlined in the
/// accent color with a check mark; [dimmed] fades a control that can't be
/// used yet and shows [hint] under its label.
class _ControlCard extends StatelessWidget {
  const _ControlCard({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.hint,
    this.dimmed = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final String? hint;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return Semantics(
      button: true,
      selected: active,
      enabled: !dimmed,
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
        child: AppCard(
          accent: active ? p.primary : null,
          accentStyle: AppCardAccent.strong,
          onTap: onTap,
          padding: EdgeInsets.symmetric(
            horizontal: AppSizes.space16.w,
            vertical: AppSizes.space16.h,
          ),
          child: Row(
            children: [
              active ? IconBox(icon, size: 48) : IconBox.neutral(icon, size: 48),
              SizedBox(width: AppSizes.space16.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.title.copyWith(color: p.text),
                    ),
                    if (hint != null)
                      Text(
                        hint!,
                        style: AppTextStyles.label.copyWith(
                          fontWeight: FontWeight.w400,
                          color: p.text2,
                        ),
                      ),
                  ],
                ),
              ),
              if (active) ...[
                SizedBox(width: AppSizes.space12.w),
                Icon(
                  Icons.check_circle_rounded,
                  size: 22.r,
                  color: p.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
