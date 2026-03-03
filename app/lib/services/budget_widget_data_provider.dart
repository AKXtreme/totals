import 'package:totals/models/budget.dart';
import 'package:totals/models/category.dart';
import 'package:totals/repositories/category_repository.dart';
import 'package:totals/services/budget_service.dart';
import 'package:totals/utils/text_utils.dart';

class BudgetWidgetSnapshot {
  final String period;
  final String periodLabel;
  final bool isEmpty;
  final String emptyMessage;
  final double assignedRaw;
  final double activityRaw;
  final double availableRaw;
  final double percentUsed;
  final String assignedLabel;
  final String activityLabel;
  final String availableLabel;
  final double needsAvailableRaw;
  final double wantsAvailableRaw;
  final String needsAvailableLabel;
  final String wantsAvailableLabel;
  final String lastUpdated;

  const BudgetWidgetSnapshot({
    required this.period,
    required this.periodLabel,
    required this.isEmpty,
    required this.emptyMessage,
    required this.assignedRaw,
    required this.activityRaw,
    required this.availableRaw,
    required this.percentUsed,
    required this.assignedLabel,
    required this.activityLabel,
    required this.availableLabel,
    required this.needsAvailableRaw,
    required this.wantsAvailableRaw,
    required this.needsAvailableLabel,
    required this.wantsAvailableLabel,
    required this.lastUpdated,
  });
}

class BudgetWidgetDataProvider {
  static const List<String> supportedPeriods = ['monthly'];

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
        .toList(growable: false);

    final combinedStatuses = <BudgetStatus>[
      ...periodStatuses,
      ...matchingCategoryStatuses,
    ];

    final hasAnyBudgets = combinedStatuses.isNotEmpty;

    final assignedRaw = combinedStatuses.fold<double>(
      0.0,
      (sum, status) => sum + status.budget.amount,
    );
    final activityRaw = combinedStatuses.fold<double>(
      0.0,
      (sum, status) => sum + status.spent,
    );
    final availableRaw = assignedRaw - activityRaw;

    final percentUsed = assignedRaw > 0
        ? ((activityRaw / assignedRaw) * 100).clamp(0.0, 999.0).toDouble()
        : 0.0;

    final needsAvailableRaw = _sumGroupAvailable(
      statuses: combinedStatuses,
      categoryById: categoryById,
      group: _BudgetGroup.needs,
    );
    final wantsAvailableRaw = _sumGroupAvailable(
      statuses: combinedStatuses,
      categoryById: categoryById,
      group: _BudgetGroup.wants,
    );

    return BudgetWidgetSnapshot(
      period: period,
      periodLabel: _periodLabel(period),
      isEmpty: !hasAnyBudgets,
      emptyMessage: "You currently don't have any budgets.",
      assignedRaw: assignedRaw,
      activityRaw: activityRaw,
      availableRaw: availableRaw,
      percentUsed: percentUsed,
      assignedLabel: formatAmountForWidget(assignedRaw),
      activityLabel: formatAmountForWidget(activityRaw),
      availableLabel: formatAmountForWidget(availableRaw),
      needsAvailableRaw: needsAvailableRaw,
      wantsAvailableRaw: wantsAvailableRaw,
      needsAvailableLabel: formatAmountForWidget(needsAvailableRaw),
      wantsAvailableLabel: formatAmountForWidget(wantsAvailableRaw),
      lastUpdated: getLastUpdatedTimestamp(),
    );
  }

  double _sumGroupAvailable({
    required List<BudgetStatus> statuses,
    required Map<int, Category> categoryById,
    required _BudgetGroup group,
  }) {
    return statuses.fold<double>(0.0, (sum, status) {
      final bucket = _groupForBudget(status.budget, categoryById);
      if (bucket != group) return sum;
      return sum + (status.budget.amount - status.spent);
    });
  }

  _BudgetGroup _groupForBudget(Budget budget, Map<int, Category> categoryById) {
    final ids = budget.selectedCategoryIds;
    if (ids.isEmpty) return _BudgetGroup.needs;

    var hasWants = false;
    var hasNeeds = false;
    for (final id in ids) {
      final category = categoryById[id];
      if (category == null) continue;
      if (category.essential) {
        hasNeeds = true;
      } else {
        hasWants = true;
      }
    }
    if (hasWants) return _BudgetGroup.wants;
    if (hasNeeds) return _BudgetGroup.needs;
    return _BudgetGroup.needs;
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

enum _BudgetGroup {
  needs,
  wants,
}
