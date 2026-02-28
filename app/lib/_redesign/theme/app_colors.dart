import 'package:flutter/material.dart';

/// Redesign color tokens sourced from lib/_redesign/theme/colors.txt.
class AppColors {
  AppColors._();

  static const Color primaryDark = Color(0xFF4F46E5);
  static const Color primaryLight = Color(0xFF6366F1);
  static const Color red = Color(0xFFEF4444);
  static const Color incomeSuccess = Color(0xFF10B981);
  static const Color amber = Color(0xFFF59E0B);
  static const Color blue = Color(0xFF3B82F6);
  static const Color white = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF8FAFC);
  static const Color surfaceAlt = Color(0xFFF8FAFC);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate900 = Color(0xFF0F172A);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate50 = Color(0xFFF8FAFC);
  static const Color border = Color(0xFFE2E8F0);
  static const Color black = Color(0xFF000000);

  // ── Theme-aware helpers ──────────────────────────────────────────────────
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color background(BuildContext context) =>
      isDark(context) ? slate900 : slate50;

  static Color cardColor(BuildContext context) =>
      isDark(context) ? slate800 : white;

  static Color textPrimary(BuildContext context) =>
      isDark(context) ? white : slate900;

  static Color textSecondary(BuildContext context) =>
      isDark(context) ? slate400 : slate500;

  static Color textTertiary(BuildContext context) =>
      isDark(context) ? slate500 : slate400;

  static Color borderColor(BuildContext context) =>
      isDark(context) ? slate700 : border;

  static Color surfaceColor(BuildContext context) =>
      isDark(context) ? slate900 : surface;
}
