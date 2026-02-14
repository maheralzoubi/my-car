import 'package:flutter/material.dart';

/// Application color palette and semantic colors.
abstract final class AppColors {
  AppColors._();

  // Primary palette
  static const Color primary = Color(0xFF6750A4);
  static const Color primaryLight = Color(0xFFE8DEF8);
  static const Color primaryDark = Color(0xFF4F378B);

  // Secondary
  static const Color secondary = Color(0xFF625B71);
  static const Color secondaryLight = Color(0xFFE7E0EC);
  static const Color secondaryDark = Color(0xFF49454F);

  // Surface & background
  static const Color surface = Color(0xFFFFFBFE);
  static const Color surfaceVariant = Color(0xFFE7E0EC);
  static const Color background = Color(0xFFFFFBFE);

  // Error & success
  static const Color error = Color(0xFFB3261E);
  static const Color errorContainer = Color(0xFFF9DEDC);
  static const Color success = Color(0xFF2E7D32);
  static const Color successContainer = Color(0xFFC8E6C9);

  // Neutral
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF1C1B1F);
  static const Color onSurfaceVariant = Color(0xFF49454F);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color outline = Color(0xFF79747E);
  static const Color outlineVariant = Color(0xFFCAC4D0);

  // Splash / Connection (CARDIAG brand)
  static const Color backgroundDark = Color(0xFF0D0D0D);
  static const Color backgroundDarkBlue = Color(0xFF0A1929);
  static const Color accentCyan = Color(0xFF00D9FF);
  static const Color accentOrange = Color(0xFFFF6B35);
  static const Color textLight = Color(0xFFE8EAED);
  static const Color surfaceDark = Color(0xFF1C1B1F);
  static const Color surfaceDarkElevated = Color(0xFF2D2D30);
  static const Color grayDark = Color(0xFF0D0D0D);
  static const Color grayMid = Color(0xFF1A1A1A);
  static const Color grayDarker = Color(0xFF2D2D2D);
  static const Color errorLight = Color(0xFFF2B8B5);
  static const Color errorDark = Color(0xFF601410);
  static const Color white = Color(0xFFFFFFFF);
  static const Color transparent = Color(0x00000000);
}
