import 'package:flutter/material.dart';

/// The app's color roles for one brightness. Read it with `context.colors`.
///
/// Design rules:
/// - [primary] (blue) is the only accent: actions, links, selection.
/// - [ok] / [warn] / [crit] are reserved for vehicle and request STATUS.
///   Each has a `*Soft` fill for pills, icon boxes and alert rows.
/// - Surfaces are solid with hairline [border]s: no glows or gradients.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.text2,
    required this.muted,
    required this.primary,
    required this.primaryButton,
    required this.onPrimary,
    required this.primarySoft,
    required this.ok,
    required this.okSoft,
    required this.warn,
    required this.warnSoft,
    required this.crit,
    required this.critSoft,
    required this.track,
    required this.scrim,
  });

  /// Screen background.
  final Color bg;

  /// Cards, sheets, dialogs, nav bar, inputs.
  final Color surface;

  /// Subtle fill inside a surface: icon boxes, segmented controls.
  final Color surface2;

  /// Hairline card / divider border.
  final Color border;

  /// Input and secondary-button border.
  final Color borderStrong;

  /// Primary text and icons.
  final Color text;

  /// Secondary text: labels, subtitles, metadata.
  final Color text2;

  /// Tertiary text, placeholders, inactive icons.
  final Color muted;

  /// Accent for links, selected states, focused borders, icons.
  final Color primary;

  /// Filled primary button / switch-on background (white text passes AA).
  final Color primaryButton;

  /// Text and icons on [primaryButton].
  final Color onPrimary;

  /// Soft accent fill: selected nav item, info pills, tile icons.
  final Color primarySoft;

  final Color ok;
  final Color okSoft;
  final Color warn;
  final Color warnSoft;
  final Color crit;
  final Color critSoft;

  /// Progress / gauge track, switch-off track.
  final Color track;

  /// Overlay behind modals and on top of media.
  final Color scrim;

  static const AppPalette light = AppPalette(
    bg: Color(0xFFF5F7FA),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF2F4F7),
    border: Color(0xFFE4E7EC),
    borderStrong: Color(0xFFD0D5DD),
    text: Color(0xFF101828),
    text2: Color(0xFF475467),
    muted: Color(0xFF667085),
    primary: Color(0xFF2563EB),
    primaryButton: Color(0xFF2563EB),
    onPrimary: Color(0xFFFFFFFF),
    primarySoft: Color(0xFFEFF4FF),
    ok: Color(0xFF067647),
    okSoft: Color(0xFFECFDF3),
    warn: Color(0xFFB54708),
    warnSoft: Color(0xFFFFFAEB),
    crit: Color(0xFFB42318),
    critSoft: Color(0xFFFEF3F2),
    track: Color(0xFFE4E7EC),
    scrim: Color(0x99101828),
  );

  static const AppPalette dark = AppPalette(
    bg: Color(0xFF0B0F17),
    surface: Color(0xFF131A26),
    surface2: Color(0xFF1A2332),
    border: Color(0xFF253044),
    borderStrong: Color(0xFF334058),
    text: Color(0xFFF2F4F7),
    text2: Color(0xFFA9B4C7),
    muted: Color(0xFF7C889D),
    primary: Color(0xFF6EA8FF),
    primaryButton: Color(0xFF2563EB),
    onPrimary: Color(0xFFFFFFFF),
    primarySoft: Color(0x246EA8FF), // 14%
    ok: Color(0xFF47CD89),
    okSoft: Color(0x2447CD89),
    warn: Color(0xFFFDB022),
    warnSoft: Color(0x24FDB022),
    crit: Color(0xFFF97066),
    critSoft: Color(0x24F97066),
    track: Color(0xFF253044),
    scrim: Color(0xB3000000),
  );

  @override
  AppPalette copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? border,
    Color? borderStrong,
    Color? text,
    Color? text2,
    Color? muted,
    Color? primary,
    Color? primaryButton,
    Color? onPrimary,
    Color? primarySoft,
    Color? ok,
    Color? okSoft,
    Color? warn,
    Color? warnSoft,
    Color? crit,
    Color? critSoft,
    Color? track,
    Color? scrim,
  }) => AppPalette(
    bg: bg ?? this.bg,
    surface: surface ?? this.surface,
    surface2: surface2 ?? this.surface2,
    border: border ?? this.border,
    borderStrong: borderStrong ?? this.borderStrong,
    text: text ?? this.text,
    text2: text2 ?? this.text2,
    muted: muted ?? this.muted,
    primary: primary ?? this.primary,
    primaryButton: primaryButton ?? this.primaryButton,
    onPrimary: onPrimary ?? this.onPrimary,
    primarySoft: primarySoft ?? this.primarySoft,
    ok: ok ?? this.ok,
    okSoft: okSoft ?? this.okSoft,
    warn: warn ?? this.warn,
    warnSoft: warnSoft ?? this.warnSoft,
    crit: crit ?? this.crit,
    critSoft: critSoft ?? this.critSoft,
    track: track ?? this.track,
    scrim: scrim ?? this.scrim,
  );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      text: l(text, other.text),
      text2: l(text2, other.text2),
      muted: l(muted, other.muted),
      primary: l(primary, other.primary),
      primaryButton: l(primaryButton, other.primaryButton),
      onPrimary: l(onPrimary, other.onPrimary),
      primarySoft: l(primarySoft, other.primarySoft),
      ok: l(ok, other.ok),
      okSoft: l(okSoft, other.okSoft),
      warn: l(warn, other.warn),
      warnSoft: l(warnSoft, other.warnSoft),
      crit: l(crit, other.crit),
      critSoft: l(critSoft, other.critSoft),
      track: l(track, other.track),
      scrim: l(scrim, other.scrim),
    );
  }
}

/// `context.colors.primary` etc. Falls back to the palette matching the
/// ambient brightness when a widget is pumped without the app theme (tests).
extension AppPaletteX on BuildContext {
  AppPalette get colors {
    final theme = Theme.of(this);
    return theme.extension<AppPalette>() ??
        (theme.brightness == Brightness.dark
            ? AppPalette.dark
            : AppPalette.light);
  }
}
