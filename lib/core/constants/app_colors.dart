import 'package:flutter/material.dart';

/// Legacy fixed (dark-only) color constants.
///
/// The redesign is light + dark: read colors from the theme with
/// `context.colors` (see `AppPalette`). Members below are kept only so code
/// compiles during migration; [white] and [transparent] stay valid.
///
/// Application color tokens.
///
/// The app is dark-only. Prefer the tokens in the first sections (brand,
/// backgrounds, text, borders, status) for all new UI. The legacy Material
/// baseline colors at the bottom are kept only so existing call sites compile
/// and will be migrated away.
abstract final class AppColors {
  AppColors._();

  // ── Brand ────────────────────────────────────────────────────────────────
  /// Primary accent: actions, links, active states, live data.
  @Deprecated('Theme-aware: use context.colors.primary (accent) / primaryButton (filled)')
  static const Color accentCyan = Color(0xFF00D9FF);

  /// Secondary accent: highlights, badges, secondary CTAs.
  @Deprecated('Theme-aware: use context.colors.warn for warnings; no orange accent in the redesign')
  static const Color accentOrange = Color(0xFFFF6B35);

  // ── Backgrounds & surfaces (darkest → lightest) ─────────────────────────
  /// Default scaffold background.
  @Deprecated('Theme-aware: use context.colors.bg')
  static const Color backgroundDark = Color(0xFF0D0D0D);

  /// Alternate deep-navy background (splash, connection, gradients).
  @Deprecated('Theme-aware: use context.colors.bg')
  static const Color backgroundDarkBlue = Color(0xFF0A1929);

  /// Cards, sheets, dialogs.
  @Deprecated('Theme-aware: use context.colors.surface')
  static const Color surfaceDark = Color(0xFF1C1B1F);

  /// Raised elements on top of a surface (menus, snackbars, selected rows).
  @Deprecated('Theme-aware: use context.colors.surface2')
  static const Color surfaceDarkElevated = Color(0xFF2D2D30);

  /// Translucent fill for glass-style cards on any background.
  @Deprecated('Theme-aware: use context.colors.surface')
  static const Color surfaceGlass = Color(0x0DFFFFFF); // white @ 5%

  // ── Text ─────────────────────────────────────────────────────────────────
  /// Primary text and icons.
  @Deprecated('Theme-aware: use context.colors.text')
  static const Color textLight = Color(0xFFE8EAED);

  /// Secondary text: labels, captions, metadata.
  @Deprecated('Theme-aware: use context.colors.text2')
  static const Color textSecondary = Color(0xFF9AA0A6);

  /// Disabled text and placeholders.
  @Deprecated('Theme-aware: use context.colors.muted')
  static const Color textMuted = Color(0xFF5F6368);

  /// Text/icons placed on a cyan or orange fill.
  @Deprecated('Theme-aware: use context.colors.onPrimary')
  static const Color onAccent = Color(0xFF0D0D0D);

  // ── Borders & dividers ───────────────────────────────────────────────────
  /// Card outlines, input borders, dividers.
  @Deprecated('Theme-aware: use context.colors.border')
  static const Color border = Color(0x1AFFFFFF); // white @ 10%

  /// Very subtle separators inside cards.
  @Deprecated('Theme-aware: use context.colors.border')
  static const Color borderSubtle = Color(0x0DFFFFFF); // white @ 5%

  // ── Status (vehicle health, alerts, DTC severity) ───────────────────────
  @Deprecated('Theme-aware: use context.colors.ok (fill: okSoft)')
  static const Color statusOk = Color(0xFF00E676);
  @Deprecated('Theme-aware: use context.colors.warn (fill: warnSoft)')
  static const Color statusWarning = Color(0xFFFFD600);
  @Deprecated('Theme-aware: use context.colors.crit (fill: critSoft)')
  static const Color statusCritical = Color(0xFFFF1744);

  // ── Utility ──────────────────────────────────────────────────────────────
  static const Color white = Color(0xFFFFFFFF);
  static const Color transparent = Color(0x00000000);

  // ── Legacy (Material baseline palette) ───────────────────────────────────
  // Not part of the app's visual language. Kept so existing screens compile;
  // migrate call sites to the tokens above.

  @Deprecated('Use accentCyan')
  static const Color primary = Color(0xFF6750A4);
  @Deprecated('Use accentCyan')
  static const Color primaryLight = Color(0xFFE8DEF8);
  @Deprecated('Use accentCyan')
  static const Color primaryDark = Color(0xFF4F378B);
  @Deprecated('Use accentOrange')
  static const Color secondary = Color(0xFF625B71);
  @Deprecated('Use surfaceDarkElevated')
  static const Color secondaryLight = Color(0xFFE7E0EC);
  @Deprecated('Use surfaceDarkElevated')
  static const Color secondaryDark = Color(0xFF49454F);
  @Deprecated('Use surfaceDark')
  static const Color surface = Color(0xFFFFFBFE);
  @Deprecated('Use surfaceDarkElevated')
  static const Color surfaceVariant = Color(0xFFE7E0EC);
  @Deprecated('Use backgroundDark')
  static const Color background = Color(0xFFFFFBFE);
  @Deprecated('Use statusCritical')
  static const Color error = Color(0xFFB3261E);
  @Deprecated('Use statusCritical with alpha')
  static const Color errorContainer = Color(0xFFF9DEDC);
  @Deprecated('Use statusCritical')
  static const Color errorLight = Color(0xFFF2B8B5);
  @Deprecated('Use statusCritical')
  static const Color errorDark = Color(0xFF601410);
  @Deprecated('Use statusOk')
  static const Color success = Color(0xFF2E7D32);
  @Deprecated('Use statusOk with alpha')
  static const Color successContainer = Color(0xFFC8E6C9);
  @Deprecated('Use onAccent')
  static const Color onPrimary = Color(0xFFFFFFFF);
  @Deprecated('Use onAccent')
  static const Color onSecondary = Color(0xFFFFFFFF);
  @Deprecated('Use textLight')
  static const Color onSurface = Color(0xFF1C1B1F);
  @Deprecated('Use textSecondary')
  static const Color onSurfaceVariant = Color(0xFF49454F);
  @Deprecated('Use white')
  static const Color onError = Color(0xFFFFFFFF);
  @Deprecated('Use textSecondary or border')
  static const Color outline = Color(0xFF79747E);
  @Deprecated('Use border')
  static const Color outlineVariant = Color(0xFFCAC4D0);
  @Deprecated('Use backgroundDark')
  static const Color grayDark = Color(0xFF0D0D0D);
  @Deprecated('Use surfaceDark')
  static const Color grayMid = Color(0xFF1A1A1A);
  @Deprecated('Use surfaceDarkElevated')
  static const Color grayDarker = Color(0xFF2D2D2D);
}
