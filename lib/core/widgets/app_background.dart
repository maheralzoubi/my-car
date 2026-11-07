import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// The standard screen background: the theme's solid [AppPalette.bg].
/// (Kept as a widget so screens can wrap their body consistently.)
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: context.colors.bg, child: child);
}
