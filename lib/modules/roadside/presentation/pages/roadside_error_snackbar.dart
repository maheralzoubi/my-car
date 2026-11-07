import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/constants/constants.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_palette.dart';

/// Shows [RoadsideState.error] (an API message or a localization key).
///
/// The snackbar keeps the theme's inverse surface; a red error icon marks it
/// as a failure. The icon uses the opposite palette's red because it sits on
/// that inverse (dark-in-light, light-in-dark) surface.
void showRoadsideError(BuildContext context, String error) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final onInverse = dark ? AppPalette.light : AppPalette.dark;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: onInverse.crit, size: 20.r),
            SizedBox(width: AppSizes.space12.w),
            Expanded(child: Text(context.tr(error))),
          ],
        ),
      ),
    );
}
