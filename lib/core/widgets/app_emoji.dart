import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// An emoji used as a decorative icon. Hidden from screen readers.
///
/// The redesign uses real icons instead: prefer [IconBox] / [Icon].
@Deprecated('Use IconBox or Icon — the redesign has no emoji icons')
class AppEmoji extends StatelessWidget {
  const AppEmoji(this.emoji, {super.key, this.size = 24});

  final String emoji;

  /// Design size in logical pixels, scaled with `.sp`.
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Text(emoji, style: TextStyle(fontSize: size.sp, height: 1)),
  );
}
