import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../theme/app_palette.dart';

/// A rounded square holding one icon — the app's replacement for emoji and
/// glowing icon circles. Leading element of list rows, tiles and cards.
///
/// Default: accent icon on the soft accent fill. [IconBox.neutral]: secondary
/// icon on a neutral fill (settings rows). Pass [color] for a status tone:
/// the fill becomes a soft version of it.
class IconBox extends StatelessWidget {
  const IconBox(
    this.icon, {
    super.key,
    this.color,
    this.size = 40,
    this.neutral = false,
  });

  const IconBox.neutral(this.icon, {super.key, this.size = 32})
    : color = null,
      neutral = true;

  final IconData icon;

  /// Icon color; the fill is a soft version of it. Defaults to the accent.
  final Color? color;

  /// Box edge in design px (icon is ~50% of it).
  final double size;

  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Color fg;
    final Color bg;
    if (neutral) {
      fg = p.text2;
      bg = p.surface2;
    } else if (color != null) {
      fg = color!;
      bg = color!.withValues(alpha: dark ? 0.16 : 0.1);
    } else {
      fg = p.primary;
      bg = p.primarySoft;
    }
    return ExcludeSemantics(
      child: Container(
        width: size.r,
        height: size.r,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular((size * 0.28).r),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: (size * 0.5).r, color: fg),
      ),
    );
  }
}
