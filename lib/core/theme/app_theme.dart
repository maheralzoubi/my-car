import 'package:flutter/material.dart';

import '../constants/constants.dart';
import 'app_palette.dart';
import 'app_text_styles.dart';

/// Application themes: [light] and [dark], built from the same rules on the
/// two [AppPalette]s. Calm surfaces, one blue accent, hairline borders.
abstract final class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(AppPalette.light, Brightness.light);
  static ThemeData get dark => _build(AppPalette.dark, Brightness.dark);

  static const String _font = AppTextStyles.fontFamily;
  static const double _rControl = 12;
  static const double _rCard = 16;
  static const double _rSheet = 20;

  static ThemeData _build(AppPalette p, Brightness b) {
    final isDark = b == Brightness.dark;
    final scheme = ColorScheme(
      brightness: b,
      primary: p.primary,
      onPrimary: isDark ? const Color(0xFF0B0F17) : p.onPrimary,
      primaryContainer: p.primarySoft,
      onPrimaryContainer: p.primary,
      secondary: p.primary,
      onSecondary: p.onPrimary,
      secondaryContainer: p.primarySoft,
      onSecondaryContainer: p.primary,
      tertiary: p.ok,
      onTertiary: p.onPrimary,
      error: p.crit,
      onError: p.onPrimary,
      errorContainer: p.critSoft,
      onErrorContainer: p.crit,
      surface: p.surface,
      onSurface: p.text,
      onSurfaceVariant: p.text2,
      surfaceContainerLowest: p.bg,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surface,
      surfaceContainerHighest: p.surface2,
      outline: p.borderStrong,
      outlineVariant: p.border,
      shadow: Colors.black,
      scrim: p.scrim,
      inverseSurface: p.text,
      onInverseSurface: p.bg,
      inversePrimary: p.primaryButton,
    );

    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_rControl),
    );
    const buttonText = TextStyle(
      fontFamily: _font,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    );
    // Height only: full-width minimums break buttons inside Rows and dialog
    // action bars. Use AppButton (expands by default) for full-width CTAs.
    const buttonSize = Size(64, 48);
    OutlineInputBorder inputBorder(Color c, [double w = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(_rControl),
          borderSide: BorderSide(color: c, width: w),
        );
    TextStyle t(double size, FontWeight w, Color c) =>
        TextStyle(fontFamily: _font, fontSize: size, fontWeight: w, color: c);

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      extensions: [p],
      fontFamily: _font,
      textTheme: AppTextStyles.materialTextTheme.apply(
        fontFamily: _font,
        bodyColor: p.text,
        displayColor: p.text,
      ),
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      dividerColor: p.border,
      splashFactory: InkSparkle.splashFactory,
      iconTheme: IconThemeData(color: p.text, size: 22),

      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: p.bg,
        foregroundColor: p.text,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: t(17, FontWeight.w600, p.text),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_rCard),
          side: BorderSide(color: p.border),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: buttonSize,
          elevation: 0,
          backgroundColor: p.primaryButton,
          foregroundColor: p.onPrimary,
          disabledBackgroundColor: p.surface2,
          disabledForegroundColor: p.muted,
          textStyle: buttonText,
          shape: controlShape,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          backgroundColor: p.primaryButton,
          foregroundColor: p.onPrimary,
          disabledBackgroundColor: p.surface2,
          disabledForegroundColor: p.muted,
          textStyle: buttonText,
          shape: controlShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          foregroundColor: p.text,
          backgroundColor: p.surface,
          side: BorderSide(color: p.borderStrong),
          textStyle: buttonText,
          shape: controlShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primary,
          textStyle: buttonText.copyWith(fontSize: 15),
          shape: controlShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: p.text),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primaryButton,
        foregroundColor: p.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        hintStyle: t(15, FontWeight.w400, p.muted),
        labelStyle: t(15, FontWeight.w400, p.text2),
        floatingLabelStyle: t(13, FontWeight.w500, p.primary),
        prefixIconColor: p.muted,
        suffixIconColor: p.muted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: inputBorder(p.borderStrong),
        enabledBorder: inputBorder(p.borderStrong),
        focusedBorder: inputBorder(p.primary, 1.5),
        errorBorder: inputBorder(p.crit),
        focusedErrorBorder: inputBorder(p.crit, 1.5),
        errorStyle: t(12, FontWeight.w400, p.crit),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_rSheet),
        ),
        titleTextStyle: t(17, FontWeight.w600, p.text),
        contentTextStyle: t(15, FontWeight.w400, p.text2),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.surface,
        showDragHandle: true,
        dragHandleColor: p.borderStrong,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(_rSheet)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.text,
        contentTextStyle: t(14, FontWeight.w500, p.bg),
        actionTextColor: isDark
            ? AppPalette.light.primary
            : AppPalette.dark.primary,
        shape: controlShape,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_rControl),
          side: BorderSide(color: p.border),
        ),
      ),

      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: p.text2,
        textColor: p.text,
        minVerticalPadding: 12,
        shape: controlShape,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.text,
        secondarySelectedColor: p.text,
        side: BorderSide(color: p.borderStrong),
        labelStyle: t(13, FontWeight.w500, p.text2),
        secondaryLabelStyle: t(13, FontWeight.w500, p.bg),
        checkmarkColor: p.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusFull),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary,
        linearTrackColor: p.track,
        circularTrackColor: Colors.transparent,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.primary,
        inactiveTrackColor: p.track,
        thumbColor: p.primary,
        overlayColor: p.primarySoft,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.primaryButton : p.track,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? p.primaryButton
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(p.onPrimary),
        side: BorderSide(color: p.borderStrong, width: 1.5),
      ),
      radioTheme: RadioThemeData(fillColor: WidgetStatePropertyAll(p.primary)),

      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.primarySoft,
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 22,
            color: s.contains(WidgetState.selected) ? p.primary : p.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => t(
            11,
            FontWeight.w500,
            s.contains(WidgetState.selected) ? p.primary : p.muted,
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.surface,
        selectedItemColor: p.primary,
        unselectedItemColor: p.muted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.text,
        unselectedLabelColor: p.text2,
        indicatorColor: p.primary,
        dividerColor: p.border,
        labelStyle: t(15, FontWeight.w600, p.text),
        unselectedLabelStyle: t(15, FontWeight.w500, p.text2),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.primary,
        selectionColor: p.primary.withValues(alpha: 0.3),
        selectionHandleColor: p.primary,
      ),
    );
  }
}
