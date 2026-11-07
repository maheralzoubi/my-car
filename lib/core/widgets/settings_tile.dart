import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../constants/constants.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';
import 'app_card.dart';
import 'app_switch.dart';

/// A row in a settings-style list: leading icon, title, optional subtitle,
/// and a trailing value + chevron, a switch, or a custom widget.
///
/// Inside a [SettingsGroup] rows render flat, separated by hairlines, in one
/// card (the recommended layout). On their own they render as a card each.
///
/// ```dart
/// SettingsGroup(title: 'Preferences', children: [
///   SettingsTile(leading: IconBox.neutral(Icons.language), title: 'Language',
///       value: 'English', onTap: …),
///   SettingsTile.toggle(leading: …, title: 'Notifications', value: on, onChanged: …),
/// ])
/// ```
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    this.leading,
    this.trailing,
    this.onTap,
    this.accent,
    this.enabled = true,
  }) : _toggleValue = null,
       _onToggle = null;

  /// A row with an [AppSwitch]. Tapping anywhere on the row toggles it, and
  /// screen readers announce the title together with the on/off state.
  /// Pass `onChanged: null` to show it disabled (the whole row fades).
  const SettingsTile.toggle({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.accent,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) : trailing = null,
       onTap = null,
       value = null,
       enabled = onChanged != null,
       _toggleValue = value,
       _onToggle = onChanged;

  final String title;
  final String? subtitle;

  /// Current value shown before the chevron, e.g. "English".
  final String? value;

  /// Typically an [IconBox.neutral].
  final Widget? leading;

  /// Overrides the default trailing widget. When null, a tappable row shows
  /// [value] (if any) and a chevron.
  final Widget? trailing;

  final VoidCallback? onTap;

  /// Colors the title (and the standalone card), e.g. the critical color for
  /// a "Delete account" row.
  final Color? accent;

  /// When false the row fades to 50% and ignores taps.
  final bool enabled;

  static const double _disabledOpacity = 0.5;

  final bool? _toggleValue;
  final ValueChanged<bool>? _onToggle;

  bool get _isToggle => _toggleValue != null;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final grouped = _GroupScope.of(context);

    final Widget? trailingWidget = _isToggle
        ? AppSwitch(
            value: _toggleValue!,
            onChanged: _onToggle,
            dimWhenDisabled: false,
          )
        : trailing ??
              (onTap != null || value != null
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (value != null)
                          Text(
                            value!,
                            style: AppTextStyles.label.copyWith(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w400,
                              color: p.text2,
                            ),
                          ),
                        if (onTap != null) ...[
                          SizedBox(width: AppSizes.space4.w),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: p.muted,
                            size: 22.r,
                          ),
                        ],
                      ],
                    )
                  : null);

    final VoidCallback? tap = !enabled
        ? null
        : _isToggle
        ? () => _onToggle!(!_toggleValue!)
        : onTap;

    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: 56.h),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.space16.w,
          vertical: AppSizes.space12.h,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              SizedBox(width: AppSizes.space12.w),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w500,
                      color: accent ?? p.text,
                    ),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: 2.h),
                    Text(
                      subtitle!,
                      style: AppTextStyles.label.copyWith(
                        fontWeight: FontWeight.w400,
                        color: p.text2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailingWidget != null) ...[
              SizedBox(width: AppSizes.space12.w),
              trailingWidget,
            ],
          ],
        ),
      ),
    );

    Widget tile = grouped
        ? Material(
            type: MaterialType.transparency,
            child: InkWell(onTap: tap, child: row),
          )
        : AppCard(
            accent: accent,
            onTap: tap,
            padding: EdgeInsets.zero,
            child: row,
          );
    if (!enabled) tile = Opacity(opacity: _disabledOpacity, child: tile);

    if (!_isToggle) return tile;
    return MergeSemantics(
      child: Semantics(toggled: _toggleValue, enabled: enabled, child: tile),
    );
  }
}

/// A titled card of [SettingsTile]s separated by hairlines — the grouped-list
/// layout used by Settings, Profile and other preference screens.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, this.title, required this.children});

  /// Small label above the card, e.g. "General".
  final String? title;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: AppSizes.space4.w,
              bottom: AppSizes.space8.h,
            ),
            child: Semantics(
              header: true,
              child: Text(
                title!,
                style: AppTextStyles.label.copyWith(
                  fontWeight: FontWeight.w600,
                  color: p.muted,
                ),
              ),
            ),
          ),
        AppCard(
          padding: EdgeInsets.zero,
          child: _GroupScope(
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: AppSizes.space16.w,
                      color: p.border,
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupScope extends InheritedWidget {
  const _GroupScope({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GroupScope>() != null;

  @override
  bool updateShouldNotify(_GroupScope oldWidget) => false;
}
