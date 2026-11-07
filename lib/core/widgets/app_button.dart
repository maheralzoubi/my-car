import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../constants/constants.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';

/// Visual weight of an [AppButton].
enum AppButtonVariant {
  /// Solid blue: the one main action on a screen.
  primary,

  /// Surface with a border: secondary actions next to a primary one.
  secondary,

  /// Red text on a surface: destructive actions (Log out, Clear codes).
  danger,

  /// No container: low-emphasis actions.
  ghost,
}

/// The app's button. Full width by default, 52 px tall ([compact]: 44 px),
/// optional leading [icon] and a [isLoading] spinner state.
///
/// Pass `onPressed: null` to disable it. While [isLoading], taps are ignored
/// but the button keeps full strength.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.variant = AppButtonVariant.primary,
    this.expand = true,
    this.compact = false,
  });

  const AppButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = true,
    this.compact = false,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.danger({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = true,
    this.compact = false,
  }) : variant = AppButtonVariant.danger;

  const AppButton.ghost({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = false,
    this.compact = true,
  }) : variant = AppButtonVariant.ghost;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final AppButtonVariant variant;

  /// Stretch to the available width.
  final bool expand;

  /// 44 px instead of 52 px tall.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final enabled = onPressed != null && !isLoading;
    final (Color bg, Color fg, Color? border) = switch (variant) {
      AppButtonVariant.primary => (p.primaryButton, p.onPrimary, null),
      AppButtonVariant.secondary => (p.surface, p.text, p.borderStrong),
      AppButtonVariant.danger => (p.surface, p.crit, p.borderStrong),
      AppButtonVariant.ghost => (Colors.transparent, p.primary, null),
    };
    final disabled = onPressed == null && !isLoading;
    final radius = BorderRadius.circular(AppSizes.radiusMd.r);
    final height = (compact ? 44 : 52).h;

    final child = isLoading
        ? SizedBox.square(
            dimension: 20.r,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20.r, color: fg),
                SizedBox(width: AppSizes.space8.w),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontSize: (compact ? 15 : 16).sp,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: disabled ? 0.45 : 1,
        child: SizedBox(
          height: height,
          width: expand ? double.infinity : null,
          child: Material(
            color: bg,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: border == null
                  ? BorderSide.none
                  : BorderSide(color: border),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSizes.space16.w),
                child: Center(widthFactor: 1, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
