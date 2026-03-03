import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:totals/_redesign/theme/app_colors.dart';

class RedesignTheme {
  RedesignTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.light(
      primary: AppColors.primaryLight,
      secondary: AppColors.blue,
      surface: AppColors.surface,
      background: AppColors.slate50,
      error: AppColors.red,
      onPrimary: AppColors.white,
      onSecondary: AppColors.white,
      onSurface: AppColors.slate900,
      onBackground: AppColors.slate900,
      onError: AppColors.white,
      surfaceVariant: AppColors.slate200,
      onSurfaceVariant: AppColors.slate600,
      outline: AppColors.border,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.slate50,
      snackBarTheme: _snackBarTheme(),
      dividerColor: AppColors.border,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.slate50,
        foregroundColor: AppColors.slate900,
      ),
      cardTheme: CardThemeData(
        color: AppColors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: AppColors.border,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.primaryLight, width: 1.5),
        ),
      ),
    );
    return _applyClashGrotesk(base);
  }

  static ThemeData dark() {
    const darkBg = AppColors.darkBg;
    const darkCard = AppColors.darkCard;
    const darkBorder = AppColors.darkBorder;

    final colorScheme = ColorScheme.dark(
      primary: AppColors.primaryDark,
      secondary: AppColors.primaryLight,
      surface: AppColors.darkSurface,
      background: darkBg,
      error: AppColors.red,
      onPrimary: AppColors.white,
      onSecondary: AppColors.white,
      onSurface: AppColors.white,
      onBackground: AppColors.white,
      onError: AppColors.white,
      surfaceVariant: darkCard,
      onSurfaceVariant: AppColors.slate400,
      outline: darkBorder,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: darkBg,
      snackBarTheme: _snackBarTheme(),
      dividerColor: darkBorder,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: darkBg,
        foregroundColor: AppColors.white,
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: darkBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.primaryLight, width: 1.5),
        ),
      ),
    );
    return _applyClashGrotesk(base);
  }

  static ThemeData _applyClashGrotesk(ThemeData base) {
    return base.copyWith(
      textTheme: GoogleFonts.spaceGroteskTextTheme(base.textTheme),
      primaryTextTheme:
          GoogleFonts.spaceGroteskTextTheme(base.primaryTextTheme),
    );
  }

  static SnackBarThemeData _snackBarTheme() {
    return SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.slate700,
      contentTextStyle: const TextStyle(
        color: AppColors.white,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      elevation: 0,
    );
  }
}
