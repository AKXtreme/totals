import 'package:totals/models/budget.dart';
import 'package:totals/models/category.dart';
import 'package:totals/repositories/category_repository.dart';
import 'package:totals/services/budget_service.dart';
import 'package:totals/utils/text_utils.dart';

class BudgetWidgetCategorySlice {
  final String name;
  final double spentRaw;
  final double limitRaw;
  final String spentLabel;
  final String colorHex;

  const BudgetWidgetCategorySlice({
    required this.name,
    required this.spentRaw,
    required this.limitRaw,
    required this.spentLabel,
    required this.colorHex,
  });
}

class BudgetWidgetSnapshot {
  final String period;
  final String periodLabel;
  final bool isEmpty;
  final String emptyMessage;
  final double spentRaw;
  final double budgetRaw;
  final double percentUsed;
  final String spentLabel;
  final String budgetLabel;
  final String lastUpdated;
  final List<BudgetWidgetCategorySlice> categories;

  const BudgetWidgetSnapshot({
    required this.period,
    required this.periodLabel,
    required this.isEmpty,
    required this.emptyMessage,
    required this.spentRaw,
    required this.budgetRaw,
    required this.percentUsed,
    required this.spentLabel,
    required this.budgetLabel,
    required this.lastUpdated,
    required this.categories,
  });
}

class BudgetWidgetDataProvider {
  static const List<String> supportedPeriods = ['daily', 'monthly', 'yearly'];

  static const List<String> _rankColors = [
    '#5AC8FA',
    '#FFB347',
    '#FF5D73',
  ];

  final BudgetService _budgetService;
  final CategoryRepository _categoryRepository;

  BudgetWidgetDataProvider({
    BudgetService? budgetService,
    CategoryRepository? categoryRepository,
  })  : _budgetService = budgetService ?? BudgetService(),
        _categoryRepository = categoryRepository ?? CategoryRepository();

  Future<Map<String, BudgetWidgetSnapshot>> getAllPeriodSnapshots() async {
    final snapshots = <String, BudgetWidgetSnapshot>{};

    final categoryStatuses = await _budgetService.getCategoryBudgetStatuses();
    final categories = await _categoryRepository.getCategories();
    final categoryById = {
      for (final category in categories)
        if (category.id != null) category.id!: category,
    };

    for (final period in supportedPeriods) {
      final periodStatuses =
          await _budgetService.getBudgetStatusesByType(period);
      snapshots[period] = _buildSnapshot(
        period: period,
        periodStatuses: periodStatuses,
        allCategoryStatuses: categoryStatuses,
        categoryById: categoryById,
      );
    }

    return snapshots;
  }

  BudgetWidgetSnapshot _buildSnapshot({
    required String period,
    required List<BudgetStatus> periodStatuses,
    required List<BudgetStatus> allCategoryStatuses,
    required Map<int, Category> categoryById,
  }) {
    final matchingCategoryStatuses = allCategoryStatuses
        .where((status) => _matchesPeriod(status.budget, period))
        .toList();

    final hasAnyBudgets =
        periodStatuses.isNotEmpty || matchingCategoryStatuses.isNotEmpty;

    final aggregateStatuses =
        periodStatuses.isNotEmpty ? periodStatuses : matchingCategoryStatuses;

    final spentRaw = aggregateStatuses.fold<double>(
      0.0,
      (sum, status) => sum + status.spent,
    );
    final budgetRaw = aggregateStatuses.fold<double>(
      0.0,
      (sum, status) => sum + status.budget.amount,
    );

    final percentUsed = budgetRaw > 0
        ? ((spentRaw / budgetRaw) * 100).clamp(0.0, 999.0).toDouble()
        : 0.0;

    final categories = _buildCategorySlices(
      statuses: matchingCategoryStatuses,
      categoryById: categoryById,
    );

    return BudgetWidgetSnapshot(
      period: period,
      periodLabel: _periodLabel(period),
      isEmpty: !hasAnyBudgets,
      emptyMessage: "You currently don't have any budgets.",
      spentRaw: spentRaw,
      budgetRaw: budgetRaw,
      percentUsed: percentUsed,
      spentLabel: formatAmountForWidget(spentRaw),
      budgetLabel: formatAmountForWidget(budgetRaw),
      lastUpdated: getLastUpdatedTimestamp(),
      categories: categories,
    );
  }

  List<BudgetWidgetCategorySlice> _buildCategorySlices({
    required List<BudgetStatus> statuses,
    required Map<int, Category> categoryById,
  }) {
    final sortedStatuses = List<BudgetStatus>.from(statuses)
      ..sort((a, b) => b.spent.compareTo(a.spent));

    return sortedStatuses.take(3).toList().asMap().entries.map((entry) {
      final rank = entry.key;
      final status = entry.value;
      final categoryName = _resolveCategoryName(status, categoryById);
      return BudgetWidgetCategorySlice(
        name: categoryName,
        spentRaw: status.spent,
        limitRaw: status.budget.amount,
        spentLabel: formatAmountForWidget(status.spent),
        colorHex: _rankColors[rank % _rankColors.length],
      );
    }).toList(growable: false);
  }

  String _resolveCategoryName(
    BudgetStatus status,
    Map<int, Category> categoryById,
  ) {
    final categoryId = status.budget.categoryId;
    if (categoryId != null) {
      final category = categoryById[categoryId];
      if (category != null && category.name.trim().isNotEmpty) {
        return category.name.trim();
      }
    }

    final name = status.budget.name.trim();
    if (name.isEmpty) return 'Category';
    return name.replaceFirst(RegExp(r'\s+budget$', caseSensitive: false), '');
  }

  bool _matchesPeriod(Budget budget, String period) {
    final frame = _normalizeTimeFrame(budget.timeFrame);
    if (frame == 'never') return true;
    return frame == period;
  }

  String _normalizeTimeFrame(String? raw) {
    final value = raw?.trim().toLowerCase();
    if (value == null || value.isEmpty) return 'monthly';
    if (value == 'unlimited') return 'never';
    return value;
  }

  String _periodLabel(String period) {
    switch (period) {
      case 'daily':
        return 'Daily';
      case 'yearly':
        return 'Yearly';
      default:
        return 'Monthly';
    }
  }

  String formatAmountForWidget(double amount) {
    if (amount.abs() >= 1000) {
      final abbreviated = formatNumberAbbreviated(amount).replaceAll(' ', '');
      return '$abbreviated ETB';
    }

    final rounded = amount.roundToDouble();
    final formatted =
        formatNumberWithComma(rounded).replaceFirst(RegExp(r'\.00$'), '');
    return '$formatted ETB';
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
