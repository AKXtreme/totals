import 'package:flutter/material.dart';
import 'package:totals/models/category.dart';

class CategoryColorOption {
  final String key;
  final Color color;
  final String label;

  const CategoryColorOption({
    required this.key,
    required this.color,
    required this.label,
  });
}

const List<CategoryColorOption> categoryColorOptions = [
  CategoryColorOption(key: 'blue', color: Color(0xFF3B82F6), label: 'Blue'),
  CategoryColorOption(
      key: 'emerald', color: Color(0xFF10B981), label: 'Emerald'),
  CategoryColorOption(key: 'amber', color: Color(0xFFF59E0B), label: 'Amber'),
  CategoryColorOption(key: 'red', color: Color(0xFFEF4444), label: 'Red'),
  CategoryColorOption(key: 'rose', color: Color(0xFFFB7185), label: 'Rose'),
  CategoryColorOption(
      key: 'magenta', color: Color(0xFFD946EF), label: 'Magenta'),
  CategoryColorOption(key: 'violet', color: Color(0xFF8B5CF6), label: 'Violet'),
  CategoryColorOption(key: 'indigo', color: Color(0xFF6366F1), label: 'Indigo'),
  CategoryColorOption(key: 'teal', color: Color(0xFF14B8A6), label: 'Teal'),
  CategoryColorOption(key: 'mint', color: Color(0xFF34D399), label: 'Mint'),
  CategoryColorOption(key: 'orange', color: Color(0xFFF97316), label: 'Orange'),
  CategoryColorOption(
      key: 'tangerine', color: Color(0xFFFF8C42), label: 'Tangerine'),
  CategoryColorOption(key: 'yellow', color: Color(0xFFEAB308), label: 'Yellow'),
  CategoryColorOption(key: 'cyan', color: Color(0xFF06B6D4), label: 'Cyan'),
  CategoryColorOption(key: 'sky', color: Color(0xFF0EA5E9), label: 'Sky'),
  CategoryColorOption(key: 'lime', color: Color(0xFF84CC16), label: 'Lime'),
  CategoryColorOption(key: 'pink', color: Color(0xFFEC4899), label: 'Pink'),
  CategoryColorOption(key: 'brown', color: Color(0xFFA16207), label: 'Brown'),
  CategoryColorOption(key: 'gray', color: Color(0xFF6B7280), label: 'Gray'),
];

const Map<String, Color> _categoryColorByKey = {
  'blue': Color(0xFF3B82F6),
  'emerald': Color(0xFF10B981),
  'amber': Color(0xFFF59E0B),
  'red': Color(0xFFEF4444),
  'rose': Color(0xFFFB7185),
  'magenta': Color(0xFFD946EF),
  'violet': Color(0xFF8B5CF6),
  'indigo': Color(0xFF6366F1),
  'teal': Color(0xFF14B8A6),
  'mint': Color(0xFF34D399),
  'orange': Color(0xFFF97316),
  'tangerine': Color(0xFFFF8C42),
  'yellow': Color(0xFFEAB308),
  'cyan': Color(0xFF06B6D4),
  'sky': Color(0xFF0EA5E9),
  'lime': Color(0xFF84CC16),
  'pink': Color(0xFFEC4899),
  'brown': Color(0xFFA16207),
  'gray': Color(0xFF6B7280),
};

String? normalizeCategoryColorKey(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

String? legacyCategoryColorKeyFromIconKey(String? iconKey) {
  if (iconKey == null || iconKey.isEmpty) return null;
  const prefix = 'color:';
  if (!iconKey.startsWith(prefix)) return null;
  return normalizeCategoryColorKey(iconKey.substring(prefix.length));
}

String? resolvedCategoryColorKey(Category category) {
  final explicit = normalizeCategoryColorKey(category.colorKey);
  if (explicit != null) return explicit;
  return legacyCategoryColorKeyFromIconKey(category.iconKey);
}

Color? customCategoryColor(Category category) {
  final key = resolvedCategoryColorKey(category);
  if (key == null) return null;
  return _categoryColorByKey[key];
}

Color categoryColorFromKey(String key, {Color? fallback}) {
  return _categoryColorByKey[key] ?? fallback ?? const Color(0xFF3B82F6);
}

String suggestedCategoryColorKey({
  required String flow,
  required bool essential,
  required bool uncategorized,
}) {
  if (uncategorized) return 'gray';
  final isIncome = flow.toLowerCase() == 'income';
  if (isIncome) return essential ? 'emerald' : 'teal';
  return essential ? 'blue' : 'amber';
}

Color categoryTypeColor(Category category, BuildContext context) {
  final custom = customCategoryColor(category);
  if (custom != null) return custom;
  if (category.uncategorized) {
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }
  final isIncome = category.flow.toLowerCase() == 'income';
  if (isIncome) {
    return category.essential ? Colors.green : Colors.teal;
  }
  return category.essential ? Colors.blue : Colors.orange;
}
