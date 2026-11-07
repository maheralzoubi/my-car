import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// The app's type scale: one family, six sizes, all responsive via `.sp`.
///
/// Styles carry NO color: text inherits the theme's text color, so the same
/// style works in light and dark. Tint with `copyWith(color: context.colors.x)`
/// (secondary text: `context.colors.text2`).
///
/// | Style      | Size | Weight | Use for                                       |
/// |------------|------|--------|-----------------------------------------------|
/// | `display`  | 28   | 600    | Screen titles on hero screens, big readouts   |
/// | `headline` | 22   | 600    | Screen titles, key numbers on cards           |
/// | `title`    | 17   | 600    | Section and card headings, list row titles    |
/// | `body`     | 15   | 400    | Default reading text                          |
/// | `label`    | 13   | 500    | Labels, subtitles, chips, units               |
/// | `caption`  | 11   | 500    | Nav labels, timestamps, tiny badges           |
///
/// [display] and [headline] use tabular figures so live values don't jitter.
abstract final class AppTextStyles {
  AppTextStyles._();

  /// Font family registered in pubspec.yaml (Arabic + Latin).
  static const String fontFamily = 'IBMPlexSansArabic';

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  static TextStyle get display => TextStyle(
    fontSize: 28.sp,
    fontWeight: FontWeight.w600,
    height: 1.28,
    fontFeatures: _tabular,
  );

  static TextStyle get headline => TextStyle(
    fontSize: 22.sp,
    fontWeight: FontWeight.w600,
    height: 1.36,
    fontFeatures: _tabular,
  );

  static TextStyle get title =>
      TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w600, height: 1.4);

  static TextStyle get body =>
      TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w400, height: 1.47);

  static TextStyle get label =>
      TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, height: 1.38);

  static TextStyle get caption =>
      TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w500, height: 1.36);

  /// Adds tabular figures to any style, for live numbers in body/label sizes.
  static TextStyle numeric(TextStyle style) =>
      style.copyWith(fontFeatures: _tabular);

  /// Material [TextTheme] on the same scale, for built-in widgets (dialogs,
  /// buttons, list tiles, text fields). Not `.sp`-scaled: the theme is built
  /// outside any widget's build context.
  static const TextTheme materialTextTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w600,
      height: 1.28,
    ),
    displayMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w600,
      height: 1.28,
    ),
    displaySmall: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w600,
      height: 1.28,
    ),
    headlineLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      height: 1.36,
    ),
    headlineMedium: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      height: 1.36,
    ),
    headlineSmall: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      height: 1.36,
    ),
    titleLarge: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      height: 1.4,
    ),
    titleMedium: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      height: 1.4,
    ),
    titleSmall: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 1.47,
    ),
    bodyLarge: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.47,
    ),
    bodyMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.47,
    ),
    bodySmall: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      height: 1.38,
    ),
    labelLarge: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    labelMedium: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      height: 1.38,
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      height: 1.36,
    ),
  );
}
