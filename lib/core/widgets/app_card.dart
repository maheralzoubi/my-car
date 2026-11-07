import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../constants/constants.dart';
import '../theme/app_palette.dart';

/// The app's standard container: a solid surface with a hairline border.
///
/// Pass [accent] to color the card (a status color for an alert card);
/// [accentStyle] picks how strongly. Pass [onTap] to make the whole card
/// tappable with an ink ripple.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.accent,
    this.accentStyle = AppCardAccent.tint,
    this.onTap,
    this.radius,
  });

  final Widget child;

  /// Inner padding. Defaults to 16.
  final EdgeInsetsGeometry? padding;

  /// Outer spacing around the card.
  final EdgeInsetsGeometry? margin;

  /// Colors the card's border (and, depending on [accentStyle], its fill).
  final Color? accent;

  /// How [accent] is applied. Ignored when [accent] is null.
  final AppCardAccent accentStyle;

  final VoidCallback? onTap;

  /// Corner radius. Defaults to 16 ([AppSizes.radiusLg]).
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final r = BorderRadius.circular((radius ?? AppSizes.radiusLg).r);
    final a = accent;
    final soft = a?.withValues(alpha: dark ? 0.14 : 0.07);
    final (Color fill, Color borderColor) = switch (a == null
        ? null
        : accentStyle) {
      null => (p.surface, p.border),
      AppCardAccent.tint => (soft!, a!.withValues(alpha: dark ? 0.32 : 0.24)),
      AppCardAccent.outline => (p.surface, a!.withValues(alpha: 0.45)),
      AppCardAccent.strong => (soft!, a!),
    };

    Widget content = Padding(
      padding: padding ?? EdgeInsets.all(AppSizes.space16.r),
      child: child,
    );
    if (onTap != null) {
      content = InkWell(onTap: onTap, borderRadius: r, child: content);
    }

    final card = Material(
      color: fill,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: r,
        side: BorderSide(color: borderColor),
      ),
      child: content,
    );

    return margin == null ? card : Padding(padding: margin!, child: card);
  }
}

/// How an [AppCard] uses its accent color.
enum AppCardAccent {
  /// Soft tinted fill + soft colored border. Alerts, banners, highlights.
  tint,

  /// Neutral surface + colored border. Informational cards that should carry
  /// a color without competing with alert cards.
  outline,

  /// Soft tinted fill + solid colored border. Active / selected / lit states.
  strong,
}
