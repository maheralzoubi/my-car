
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../constants/app_colors.dart';

/// The app's type scale: six styles, all responsive via `.sp`.
///
/// Use these instead of ad-hoc `TextStyle(fontSize: …)`. Adjust a single
/// property with `copyWith`, e.g. `AppTextStyles.body.copyWith(color: …)`.
///
/// | Style      | Size | Weight | Use for                                     |
/// |------------|------|--------|---------------------------------------------|
/// | `display`  | 32   | 700    | Big live readouts: speed, RPM, drive score  |
/// | `headline` | 24   | 700    | Screen hero titles, key numbers on cards    |
/// | `title`    | 18   | 600    | App bar titles, card and section headers    |
/// | `body`     | 15   | 400    | Default reading text, list item titles      |
/// | `label`    | 13   | 500    | Secondary text, chips, small buttons, units |
/// | `caption`  | 11   | 400    | Timestamps, footnotes, tile captions        |
///
/// Numeric styles ([display], [headline]) use tabular figures so live values
/// don't jitter as digits change.
abstract final class AppTextStyles {
  AppTextStyles._();

  /// Font family registered in pubspec.yaml.
  static const String fontFamily = 'IBMPlexSansArabic';

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  static TextStyle get display => TextStyle(
    fontSize: 32.sp,
    fontWeight: FontWeight.w700,
    height: 1.1,
    color: AppColors.textLight,
    fontFeatures: _tabular,
  );

  static TextStyle get headline => TextStyle(
    fontSize: 24.sp,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: AppColors.textLight,
    fontFeatures: _tabular,
  );

  static TextStyle get title => TextStyle(
    fontSize: 18.sp,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.textLight,
  );

  static TextStyle get body => TextStyle(
    fontSize: 15.sp,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.textLight,
  );

  static TextStyle get label => TextStyle(
    fontSize: 13.sp,
    fontWeight: FontWeight.w500,
    height: 1.35,
    color: AppColors.textLight,
  );

  static TextStyle get caption => TextStyle(
    fontSize: 11.sp,
    fontWeight: FontWeight.w400,
    height: 1.3,
    color: AppColors.textSecondary,
  );

  /// Material [TextTheme] mapped onto the same six sizes, used by built-in
  /// widgets (dialogs, buttons, list tiles, text fields). Not `.sp`-scaled,
  /// since the theme is built outside any widget's build context.
  static const TextTheme materialTextTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      height: 1.1,
    ),
    displayMedium: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      height: 1.1,
    ),
    displaySmall: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      height: 1.1,
    ),
    headlineLarge: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 1.2,
    ),
    headlineMedium: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 1.2,
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 1.2,
    ),
    titleLarge: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    titleMedium: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    titleSmall: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 1.45,
    ),
    bodyLarge: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.45,
    ),
    bodyMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.45,
    ),
    bodySmall: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      height: 1.35,
    ),
    labelLarge: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    labelMedium: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      height: 1.35,
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      height: 1.3,
    ),
  );
}
