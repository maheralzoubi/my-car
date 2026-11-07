import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../constants/constants.dart';
import '../theme/app_palette.dart';
import '../theme/app_text_styles.dart';

/// Top-of-screen row: back (or close) button, title + optional subtitle,
/// optional actions.
///
/// The back button shows only when there is a page to go back to (so tab
/// roots in the bottom-navigation shell get none), unless [showBack] forces
/// it. The title ellipsizes so actions never get pushed off-screen, and the
/// back arrow mirrors in RTL.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.showBack,
    this.close = false,
    this.onBack,
  });

  final String title;

  /// Small secondary line under the title, e.g. "Last scan · 2 min ago".
  final String? subtitle;

  /// Trailing widgets, typically [HeaderAction]s.
  final List<Widget> actions;

  /// null (default): show when `Navigator.canPop`. true/false: force.
  final bool? showBack;

  /// Shows a close (✕) instead of a back arrow (full-screen forms).
  final bool close;

  /// Defaults to `Navigator.maybePop`.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final l10n = MaterialLocalizations.of(context);
    final back = showBack ?? (onBack != null || Navigator.canPop(context));
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        back ? AppSizes.space8.w : AppSizes.space20.w,
        AppSizes.space12.h,
        AppSizes.space16.w,
        AppSizes.space12.h,
      ),
      child: Row(
        children: [
          if (back) ...[
            IconButton(
              icon: Icon(
                close ? Icons.close_rounded : Icons.arrow_back_rounded,
              ),
              color: p.text,
              tooltip: close ? l10n.closeButtonTooltip : l10n.backButtonTooltip,
              onPressed: onBack ?? () => Navigator.maybePop(context),
            ),
            SizedBox(width: AppSizes.space4.w),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.headline.copyWith(color: p.text),
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
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
          for (final a in actions) ...[SizedBox(width: AppSizes.space8.w), a],
        ],
      ),
    );
  }
}

/// A 44 px outlined icon button for [ScreenHeader.actions].
class HeaderAction extends StatelessWidget {
  const HeaderAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Icon color; defaults to the primary text color.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return SizedBox.square(
      dimension: 44.r,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 20.r, color: color ?? p.text),
        style: IconButton.styleFrom(
          backgroundColor: p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd.r),
            side: BorderSide(color: p.border),
          ),
        ),
      ),
    );
  }
}
