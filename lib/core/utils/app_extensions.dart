import 'package:flutter/material.dart';

import '../constants/app_sizes.dart';

/// BuildContext extensions for theme, media, and navigation.
extension BuildContextX on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get textTheme => theme.textTheme;
  ColorScheme get colorScheme => theme.colorScheme;
  MediaQueryData get mediaQuery => MediaQuery.of(this);
  Size get screenSize => mediaQuery.size;
  EdgeInsets get padding => mediaQuery.padding;
  bool get isKeyboardVisible => mediaQuery.viewInsets.bottom > 0;

  void hideKeyboard() {
    FocusScope.of(this).unfocus();
  }
}

/// String extensions for validation and formatting.
extension StringX on String {
  bool get isBlank => trim().isEmpty;
  bool get isNotBlank => !isBlank;
}

/// Num extensions for responsive spacing.
extension NumX on num {
  SizedBox get verticalSpace => SizedBox(height: toDouble());
  SizedBox get horizontalSpace => SizedBox(width: toDouble());
}

/// Spacing shorthand using AppSizes.
extension SpacingX on Widget {
  Widget paddingAll(double value) =>
      Padding(padding: EdgeInsets.all(value), child: this);

  Widget paddingSymmetric({double horizontal = 0, double vertical = 0}) =>
      Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontal,
          vertical: vertical,
        ),
        child: this,
      );

  Widget get paddingStandard =>
      Padding(padding: const EdgeInsets.all(AppSizes.space16), child: this);
}
