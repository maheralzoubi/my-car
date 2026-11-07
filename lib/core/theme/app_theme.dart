import 'package:flutter/material.dart';

import '../constants/constants.dart';
import 'app_text_styles.dart';

/// Application theme. The app is dark-only, built on the cyan / orange
/// brand palette in [AppColors].
abstract final class AppTheme {
  AppTheme._();

  static const String _font = AppTextStyles.fontFamily;

  static const double _radiusControl = 12;
  static const double _radiusCard = 16;
  static const double _radiusSheet = 20;

  static final OutlineInputBorder _inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_radiusControl),
    borderSide: const BorderSide(color: AppColors.border),
  );

  static ThemeData get dark {
    const colorScheme = ColorScheme.dark(
      primary: AppColors.accentCyan,
      onPrimary: AppColors.onAccent,
      primaryContainer: Color(0xFF00363F),
      onPrimaryContainer: AppColors.accentCyan,
      secondary: AppColors.accentOrange,
      onSecondary: AppColors.onAccent,
      secondaryContainer: Color(0xFF3D1A0D),
      onSecondaryContainer: AppColors.accentOrange,
      tertiary: AppColors.statusOk,
      onTertiary: AppColors.onAccent,
      surface: AppColors.backgroundDark,
      onSurface: AppColors.textLight,
      surfaceContainerLowest: AppColors.backgroundDark,
      surfaceContainerLow: AppColors.surfaceDark,
      surfaceContainer: AppColors.surfaceDark,
      surfaceContainerHigh: AppColors.surfaceDarkElevated,
      surfaceContainerHighest: AppColors.surfaceDarkElevated,
      onSurfaceVariant: AppColors.textSecondary,
      error: AppColors.statusCritical,
      onError: AppColors.white,
      outline: AppColors.border,
      outlineVariant: AppColors.borderSubtle,
      shadow: Colors.black,
      scrim: Colors.black,
    );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_radiusControl),
    );
    const buttonText = TextStyle(
      fontFamily: _font,
      fontSize: 15,
      fontWeight: FontWeight.w600,
    );
    // Height only: a full-width minimum would break buttons inside Rows and
    // dialog action bars. Wrap in SizedBox(width: double.infinity) for
    // full-width buttons.
    const buttonSize = Size(64, AppSizes.buttonHeight);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      fontFamily: _font,
      textTheme: AppTextStyles.materialTextTheme.apply(
        bodyColor: AppColors.textLight,
        displayColor: AppColors.textLight,
      ),
      scaffoldBackgroundColor: AppColors.backgroundDark,
      canvasColor: AppColors.backgroundDark,
      splashFactory: InkSparkle.splashFactory,
      dividerColor: AppColors.border,
      iconTheme: const IconThemeData(color: AppColors.textLight),

      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textLight,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: _font,
          color: AppColors.textLight,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: AppColors.surfaceDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusCard),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: buttonSize,
          elevation: 0,
          backgroundColor: AppColors.accentCyan,
          foregroundColor: AppColors.onAccent,
          disabledBackgroundColor: AppColors.surfaceDarkElevated,
          disabledForegroundColor: AppColors.textMuted,
          textStyle: buttonText,
          shape: buttonShape,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          backgroundColor: AppColors.accentCyan,
          foregroundColor: AppColors.onAccent,
          disabledBackgroundColor: AppColors.surfaceDarkElevated,
          disabledForegroundColor: AppColors.textMuted,
          textStyle: buttonText,
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          foregroundColor: AppColors.accentCyan,
          side: const BorderSide(color: AppColors.accentCyan),
          textStyle: buttonText,
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentCyan,
          textStyle: buttonText,
          shape: buttonShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.textLight),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accentCyan,
        foregroundColor: AppColors.onAccent,
        elevation: 4,
        focusElevation: 6,
        hoverElevation: 6,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceGlass,
        hintStyle: const TextStyle(
          fontFamily: _font,
          color: AppColors.textMuted,
        ),
        labelStyle: const TextStyle(
          fontFamily: _font,
          color: AppColors.textSecondary,
        ),
        floatingLabelStyle: const TextStyle(
          fontFamily: _font,
          color: AppColors.accentCyan,
        ),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSizes.space16,
          vertical: AppSizes.space12,
        ),
        border: _inputBorder,
        enabledBorder: _inputBorder,
        focusedBorder: _inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.accentCyan, width: 1.5),
        ),
        errorBorder: _inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.statusCritical),
        ),
        focusedErrorBorder: _inputBorder.copyWith(
          borderSide: const BorderSide(
            color: AppColors.statusCritical,
            width: 1.5,
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusSheet),
          side: const BorderSide(color: AppColors.border),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: _font,
          color: AppColors.textLight,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: _font,
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceDark,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surfaceDark,
        showDragHandle: true,
        dragHandleColor: AppColors.textMuted,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(_radiusSheet),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceDarkElevated,
        contentTextStyle: const TextStyle(
          fontFamily: _font,
          color: AppColors.textLight,
        ),
        actionTextColor: AppColors.accentCyan,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusControl),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceDarkElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusControl),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textLight,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceGlass,
        selectedColor: AppColors.accentCyan.withValues(alpha: 0.15),
        side: const BorderSide(color: AppColors.border),
        labelStyle: const TextStyle(
          fontFamily: _font,
          color: AppColors.textLight,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusFull),
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accentCyan,
        linearTrackColor: AppColors.border,
        circularTrackColor: Colors.transparent,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.accentCyan,
        inactiveTrackColor: AppColors.border,
        thumbColor: AppColors.accentCyan,
        overlayColor: AppColors.accentCyan.withValues(alpha: 0.12),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.onAccent
              : AppColors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.accentCyan
              : AppColors.surfaceDarkElevated,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.transparent
              : AppColors.border,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.accentCyan
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(AppColors.onAccent),
        side: const BorderSide(color: AppColors.textSecondary, width: 1.5),
      ),
      radioTheme: const RadioThemeData(
        fillColor: WidgetStatePropertyAll(AppColors.accentCyan),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surfaceDark,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.accentCyan.withValues(alpha: 0.15),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected)
                ? AppColors.accentCyan
                : AppColors.textSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontFamily: _font,
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            color: s.contains(WidgetState.selected)
                ? AppColors.accentCyan
                : AppColors.textSecondary,
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceDark,
        selectedItemColor: AppColors.accentCyan,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.accentCyan,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.accentCyan,
        dividerColor: AppColors.border,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.accentCyan,
        selectionColor: AppColors.accentCyan.withValues(alpha: 0.3),
        selectionHandleColor: AppColors.accentCyan,
      ),
    );
  }
}
