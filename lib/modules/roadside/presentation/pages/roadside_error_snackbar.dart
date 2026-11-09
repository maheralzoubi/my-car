import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/localization/app_localizations.dart';

/// Shows [RoadsideState.error] (an API message or a localization key).
void showRoadsideError(BuildContext context, String error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(context.tr(error)),
      backgroundColor: AppColors.error,
    ));
}
