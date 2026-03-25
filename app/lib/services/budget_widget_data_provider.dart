import 'package:flutter/material.dart';
import 'package:totals/models/budget.dart';
import 'package:totals/models/category.dart';
import 'package:totals/repositories/category_repository.dart';
import 'package:totals/services/budget_service.dart';

class BudgetWidgetBudgetSnapshot {
  final int budgetId;
  final String name;
  final double spentRaw;
  final double amountRaw;
  final double percentUsed;
  final double ringPercent;
  final String compactValueLabel;
  final String expandedValueLabel;
  final String colorHex;

  const BudgetWidgetBudgetSnapshot({
    required this.budgetId,
    required this.name,
    required this.spentRaw,
    required this.amountRaw,
    required this.percentUsed,
    required this.ringPercent,
    required this.compactValueLabel,
    required this.expandedValueLabel,
    required this.colorHex,
  });
}

class BudgetWidgetPayload {
  final Map<int, BudgetWidgetBudgetSnapshot> budgetsById;
  final bool hasAnyBudgets;
  final String emptyMessage;
  final String lastUpdated;

  const BudgetWidgetPayload({
    required this.budgetsById,
    required this.hasAnyBudgets,
    required this.emptyMessage,
    required this.lastUpdated,
  });
}

class BudgetWidgetDataProvider {
  final BudgetService _budgetService;
  final CategoryRepository _categoryRepository;

  BudgetWidgetDataProvider({
    BudgetService? budgetService,
    CategoryRepository? categoryRepository,
  })  : _budgetService = budgetService ?? BudgetService(),
        _categoryRepository = categoryRepository ?? CategoryRepository();

  Future<BudgetWidgetPayload> getWidgetPayload() async {
    final statuses = await _budgetService.getAllBudgetStatuses();
    final visibleStatuses = statuses
        .where(
          (status) => status.budget.overlapsRange(
            status.periodStart,
            status.periodEnd,
          ),
        )
        .toList(growable: false);

    final categories = await _categoryRepository.getCategories();
    final categoryById = {
      for (final category in categories)
        if (category.id != null) category.id!: category,
    };

    final budgetsById = <int, BudgetWidgetBudgetSnapshot>{};
    for (final status in visibleStatuses) {
      final budgetId = status.budget.id;
      if (budgetId == null) continue;
      budgetsById[budgetId] = _buildBudgetSnapshot(
        status: status,
        categoryById: categoryById,
      );
    }

    final hasAnyBudgets = budgetsById.isNotEmpty;

    return BudgetWidgetPayload(
      budgetsById: budgetsById,
      hasAnyBudgets: hasAnyBudgets,
      emptyMessage: hasAnyBudgets
          ? 'Choose up to 3 budgets in Totals.'
          : 'Create a budget to show it here.',
      lastUpdated: getLastUpdatedTimestamp(),
    );
  }

  BudgetWidgetBudgetSnapshot _buildBudgetSnapshot({
    required BudgetStatus status,
    required Map<int, Category> categoryById,
  }) {
    final budget = status.budget;
    final color = _resolveBudgetColor(
      budget: budget,
      categoryById: categoryById,
    );
    final budgetName =
        budget.name.trim().isEmpty ? 'Budget' : budget.name.trim();
    final spentLabel = _formatMetricNumber(status.spent);
    final amountLabel = _formatMetricNumber(budget.amount);

    return BudgetWidgetBudgetSnapshot(
      budgetId: budget.id!,
      name: budgetName,
      spentRaw: status.spent,
      amountRaw: budget.amount,
      percentUsed: status.percentageUsed,
      ringPercent: status.percentageUsed.clamp(0.0, 100.0).toDouble(),
      compactValueLabel: spentLabel,
      expandedValueLabel: '$spentLabel / $amountLabel',
      colorHex: _colorToHex(color),
    );
  }

  Color _resolveBudgetColor({
    required Budget budget,
    required Map<int, Category> categoryById,
  }) {
    final categories = budget.selectedCategoryIds
        .map((id) => categoryById[id])
        .whereType<Category>()
        .toList(growable: false);

    for (final category in categories) {
      final explicitColorKey = _normalizeColorKey(category.colorKey) ??
          _extractLegacyColorKey(category.iconKey);
      if (explicitColorKey != null) {
        return _colorFromKey(explicitColorKey);
      }
    }

    final seed = categories.isNotEmpty
        ? categories.map((category) => category.name).join('|')
        : budget.name;
    return _kBudgetWidgetPalette[
        _hashSeed(seed) % _kBudgetWidgetPalette.length];
  }

  String? _normalizeColorKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  String? _extractLegacyColorKey(String? iconKey) {
    if (iconKey == null || iconKey.isEmpty) return null;
    const prefix = 'color:';
    if (!iconKey.startsWith(prefix)) return null;
    final value = iconKey.substring(prefix.length).trim();
    if (value.isEmpty) return null;
    return value;
  }

  Color _colorFromKey(String colorKey) {
    return _kBudgetWidgetColors[colorKey] ?? _kBudgetWidgetPalette.first;
  }

  int _hashSeed(String value) {
    var hash = 0;
    for (final codeUnit in value.trim().toLowerCase().codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0x7fffffff;
    }
    return hash;
  }

  String _formatMetricNumber(double amount) {
    final absolute = amount.abs();
    final sign = amount < 0 ? '-' : '';

    if (absolute >= 1000000) {
      final value = absolute / 1000000;
      return '$sign${_formatCompactDecimal(value)}M';
    }
    if (absolute >= 1000) {
      final value = absolute / 1000;
      return '$sign${_formatCompactDecimal(value)}K';
    }
    if (absolute >= 100) {
      return '$sign${absolute.round()}';
    }
    if (absolute == absolute.roundToDouble()) {
      return '$sign${absolute.toInt()}';
    }
    return '$sign${absolute.toStringAsFixed(1)}';
  }

  String _formatCompactDecimal(double value) {
    final formatted = value.toStringAsFixed(value >= 10 ? 0 : 1);
    return formatted.replaceFirst(RegExp(r'\.0$'), '');
  }

  String _colorToHex(Color color) {
    final red = (color.r * 255).round().toRadixString(16).padLeft(2, '0');
    final green = (color.g * 255).round().toRadixString(16).padLeft(2, '0');
    final blue = (color.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#${(red + green + blue).toUpperCase()}';
  }

  String getLastUpdatedTimestamp() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$month/$day, $hour:$minute';
  }
}

const Map<String, Color> _kBudgetWidgetColors = {
  'blue': Color(0xFF60A5FA),
  'emerald': Color(0xFF34D399),
  'amber': Color(0xFFFBBF24),
  'red': Color(0xFFFB7185),
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
  'gray': Color(0xFF94A3B8),
};

const List<Color> _kBudgetWidgetPalette = [
  Color(0xFF34D399),
  Color(0xFF60A5FA),
  Color(0xFFEC4899),
  Color(0xFFF59E0B),
  Color(0xFF8B5CF6),
  Color(0xFF06B6D4),
  Color(0xFFF97316),
  Color(0xFF84CC16),
];
