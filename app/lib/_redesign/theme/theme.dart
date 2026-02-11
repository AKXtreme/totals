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
    final colorScheme = ColorScheme.dark(
      primary: AppColors.primaryDark,
      secondary: AppColors.blue,
      surface: AppColors.slate900,
      background: AppColors.slate900,
      error: AppColors.red,
      onPrimary: AppColors.white,
      onSecondary: AppColors.white,
      onSurface: AppColors.white,
      onBackground: AppColors.white,
      onError: AppColors.white,
      surfaceVariant: AppColors.slate800,
      onSurfaceVariant: AppColors.slate400,
      outline: AppColors.slate700,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.slate900,
      dividerColor: AppColors.slate700,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.slate900,
        foregroundColor: AppColors.white,
      ),
      cardTheme: CardThemeData(
        color: AppColors.slate800,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.slate700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.slate800,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.slate700),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.slate700),
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
}
