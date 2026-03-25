import 'dart:convert';

import 'package:home_widget/home_widget.dart';
import 'package:totals/services/budget_widget_data_provider.dart';
import 'package:totals/services/widget_data_provider.dart';
import 'package:totals/services/widget_refresh_state_service.dart';

class WidgetService {
  static const String appGroupId = 'group.com.example.totals.widget';

  static const String expenseAndroidWidgetName = 'ExpenseWidgetProvider';
  static const String expenseAndroidWidgetQualifiedName =
      'com.example.offline_gateway.$expenseAndroidWidgetName';

  static const String budgetAndroidWidgetName = 'BudgetWidgetProvider';
  static const String budgetAndroidWidgetQualifiedName =
      'com.example.offline_gateway.$budgetAndroidWidgetName';
  static const int maxBudgetWidgetBudgets = 3;

  static const String _budgetWidgetSelectedIdsKey =
      'budget_widget_selected_ids';
  static const String _budgetWidgetSelectedCountKey =
      'budget_widget_selected_count';
  static const String _budgetWidgetEmptyMessageKey =
      'budget_widget_empty_message';
  static const String _budgetWidgetLastUpdatedKey =
      'budget_widget_last_updated';

  static WidgetDataProvider? _dataProvider;
  static BudgetWidgetDataProvider? _budgetDataProvider;

  static WidgetDataProvider get dataProvider {
    _dataProvider ??= WidgetDataProvider();
    return _dataProvider!;
  }

  static BudgetWidgetDataProvider get budgetDataProvider {
    _budgetDataProvider ??= BudgetWidgetDataProvider();
    return _budgetDataProvider!;
  }

  /// Initialize the widget plugin.
  static Future<void> initialize() async {
    await HomeWidget.setAppGroupId(appGroupId);
  }

  /// Refresh all home screen widgets.
  static Future<void> refreshWidget() async {
    await refreshAllWidgets();
  }

  /// Refresh all widgets and update global refresh timestamp.
  static Future<void> refreshAllWidgets() async {
    try {
      await _refreshExpenseWidget();
    } catch (e) {
      print('Error refreshing expense widget: $e');
    }

    await refreshBudgetWidget(updateRefreshState: false);
    await WidgetRefreshStateService.instance.setLastRefreshAt(DateTime.now());
  }

  static Future<void> _refreshExpenseWidget() async {
    final todaySpending = await dataProvider.getTodaySpending();
    final formattedAmount = dataProvider.formatAmountForWidget(todaySpending);
    final todayIncome = await dataProvider.getTodayIncome();
    final formattedIncome = dataProvider.formatAmountForWidget(todayIncome);
    final lastUpdated = dataProvider.getLastUpdatedTimestamp();
    final categories = await dataProvider.getTodayCategoryBreakdown();
    final incomeCategories =
        await dataProvider.getTodayIncomeCategoryBreakdown();

    await HomeWidget.saveWidgetData<String>('expense_total', formattedAmount);
    await HomeWidget.saveWidgetData<String>(
      'expense_total_raw',
      todaySpending.toString(),
    );
    await HomeWidget.saveWidgetData<String>(
        'expense_last_updated', lastUpdated);

    final categoryJson = jsonEncode(categories.map((c) => c.toJson()).toList());
    await HomeWidget.saveWidgetData<String>('expense_categories', categoryJson);

    await HomeWidget.saveWidgetData<String>('income_total', formattedIncome);
    await HomeWidget.saveWidgetData<String>(
      'income_total_raw',
      todayIncome.toString(),
    );
    await HomeWidget.saveWidgetData<String>('income_last_updated', lastUpdated);

    final incomeCategoryJson =
        jsonEncode(incomeCategories.map((c) => c.toJson()).toList());
    await HomeWidget.saveWidgetData<String>(
      'income_categories',
      incomeCategoryJson,
    );

    await _saveCategoryData(prefix: 'category', categories: categories);
    await _saveCategoryData(
        prefix: 'income_category', categories: incomeCategories);

    await HomeWidget.updateWidget(androidName: expenseAndroidWidgetName);

    print(
      'Expense widget updated: $formattedAmount / $formattedIncome at $lastUpdated',
    );
  }

  static Future<void> refreshBudgetWidget({
    bool updateRefreshState = true,
  }) async {
    try {
      final payload = await budgetDataProvider.getWidgetPayload();
      final selectedIds = await getBudgetWidgetSelectedIds();
      final sanitizedIds = selectedIds
          .where(payload.budgetsById.containsKey)
          .take(maxBudgetWidgetBudgets)
          .toList(growable: false);

      if (!_sameIds(selectedIds, sanitizedIds)) {
        await _saveBudgetWidgetSelectedIds(sanitizedIds);
      }

      await HomeWidget.saveWidgetData<String>(
        _budgetWidgetSelectedCountKey,
        sanitizedIds.length.toString(),
      );
      await HomeWidget.saveWidgetData<String>(
        _budgetWidgetEmptyMessageKey,
        sanitizedIds.isEmpty
            ? payload.emptyMessage
            : 'Choose up to $maxBudgetWidgetBudgets budgets in Totals.',
      );
      await HomeWidget.saveWidgetData<String>(
        _budgetWidgetLastUpdatedKey,
        payload.lastUpdated,
      );

      for (var index = 0; index < maxBudgetWidgetBudgets; index++) {
        final prefix = 'budget_item_$index';
        if (index < sanitizedIds.length) {
          final snapshot = payload.budgetsById[sanitizedIds[index]];
          if (snapshot != null) {
            await HomeWidget.saveWidgetData<String>(
              '${prefix}_budget_id',
              snapshot.budgetId.toString(),
            );
            await HomeWidget.saveWidgetData<String>(
              '${prefix}_name',
              snapshot.name,
            );
            await HomeWidget.saveWidgetData<String>(
              '${prefix}_compact_value',
              snapshot.compactValueLabel,
            );
            await HomeWidget.saveWidgetData<String>(
              '${prefix}_expanded_value',
              snapshot.expandedValueLabel,
            );
            await HomeWidget.saveWidgetData<String>(
              '${prefix}_spent_raw',
              snapshot.spentRaw.toString(),
            );
            await HomeWidget.saveWidgetData<String>(
              '${prefix}_amount_raw',
              snapshot.amountRaw.toString(),
            );
            await HomeWidget.saveWidgetData<String>(
              '${prefix}_percent',
              snapshot.percentUsed.toString(),
            );
            await HomeWidget.saveWidgetData<String>(
              '${prefix}_ring_percent',
              snapshot.ringPercent.toString(),
            );
            await HomeWidget.saveWidgetData<String>(
              '${prefix}_color',
              snapshot.colorHex,
            );
            continue;
          }
        }

        await HomeWidget.saveWidgetData<String>('${prefix}_budget_id', '');
        await HomeWidget.saveWidgetData<String>('${prefix}_name', '');
        await HomeWidget.saveWidgetData<String>('${prefix}_compact_value', '');
        await HomeWidget.saveWidgetData<String>('${prefix}_expanded_value', '');
        await HomeWidget.saveWidgetData<String>('${prefix}_spent_raw', '0');
        await HomeWidget.saveWidgetData<String>('${prefix}_amount_raw', '0');
        await HomeWidget.saveWidgetData<String>('${prefix}_percent', '0');
        await HomeWidget.saveWidgetData<String>('${prefix}_ring_percent', '0');
        await HomeWidget.saveWidgetData<String>('${prefix}_color', '');
      }

      await HomeWidget.updateWidget(androidName: budgetAndroidWidgetName);

      if (updateRefreshState) {
        await WidgetRefreshStateService.instance
            .setLastRefreshAt(DateTime.now());
      }

      print('Budget widget updated');
    } catch (e) {
      print('Error updating budget widget: $e');
    }
  }

  static Future<void> _saveCategoryData({
    required String prefix,
    required List<CategoryExpense> categories,
  }) async {
    for (int i = 0; i < 3; i++) {
      if (i < categories.length) {
        final category = categories[i];
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_${i}_name',
          category.name,
        );
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_${i}_amount',
          dataProvider.formatAmountForWidget(category.amount),
        );
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_${i}_amount_raw',
          category.amount.toString(),
        );
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_${i}_color',
          category.colorHex,
        );
      } else {
        await HomeWidget.saveWidgetData<String>('${prefix}_${i}_name', '');
        await HomeWidget.saveWidgetData<String>('${prefix}_${i}_amount', '');
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_${i}_amount_raw',
          '0',
        );
        await HomeWidget.saveWidgetData<String>('${prefix}_${i}_color', '');
      }
    }
  }

  /// Send basic expense data to the existing expense widget.
  static Future<void> updateWidgetData({
    required String totalAmount,
    required String lastUpdated,
  }) async {
    await HomeWidget.saveWidgetData<String>('expense_total', totalAmount);
    await HomeWidget.saveWidgetData<String>(
        'expense_last_updated', lastUpdated);
    await HomeWidget.updateWidget(
      qualifiedAndroidName: expenseAndroidWidgetQualifiedName,
    );
    await WidgetRefreshStateService.instance.setLastRefreshAt(DateTime.now());
  }

  static Future<List<int>> getBudgetWidgetSelectedIds() async {
    final raw = await HomeWidget.getWidgetData<String>(
      _budgetWidgetSelectedIdsKey,
      defaultValue: '[]',
    );
    return _decodeIntList(raw);
  }

  static Future<BudgetWidgetSelectionResult> addBudgetToWidget(
    int budgetId,
  ) async {
    final selectedIds = await getBudgetWidgetSelectedIds();
    if (selectedIds.contains(budgetId)) {
      return BudgetWidgetSelectionResult.alreadySelected;
    }
    if (selectedIds.length >= maxBudgetWidgetBudgets) {
      return BudgetWidgetSelectionResult.limitReached;
    }

    final nextIds = [...selectedIds, budgetId];
    await _saveBudgetWidgetSelectedIds(nextIds);
    await refreshBudgetWidget();
    return BudgetWidgetSelectionResult.added;
  }

  static Future<bool> removeBudgetFromWidget(int budgetId) async {
    final selectedIds = await getBudgetWidgetSelectedIds();
    if (!selectedIds.contains(budgetId)) return false;

    final nextIds = selectedIds.where((id) => id != budgetId).toList();
    await _saveBudgetWidgetSelectedIds(nextIds);
    await refreshBudgetWidget();
    return true;
  }

  static Future<int> getInstalledBudgetWidgetCount() async {
    try {
      final widgets = await HomeWidget.getInstalledWidgets();
      return widgets.where(_isInstalledBudgetWidget).length;
    } catch (_) {
      return 0;
    }
  }

  static Future<bool> isBudgetWidgetPinSupported() async {
    return await HomeWidget.isRequestPinWidgetSupported() ?? false;
  }

  static Future<bool> requestBudgetWidgetPinIfNeeded() async {
    final installedCount = await getInstalledBudgetWidgetCount();
    if (installedCount > 0) return false;

    final supported = await isBudgetWidgetPinSupported();
    if (!supported) return false;

    await HomeWidget.requestPinWidget(androidName: budgetAndroidWidgetName);
    return true;
  }

  static bool _isInstalledBudgetWidget(HomeWidgetInfo widget) {
    final className = widget.androidClassName?.trim();
    return className == budgetAndroidWidgetQualifiedName ||
        className == budgetAndroidWidgetName ||
        className?.endsWith('.$budgetAndroidWidgetName') == true;
  }

  static Future<void> _saveBudgetWidgetSelectedIds(List<int> ids) async {
    final sanitized = ids
        .where((id) => id > 0)
        .toSet()
        .take(maxBudgetWidgetBudgets)
        .toList(growable: false);
    await HomeWidget.saveWidgetData<String>(
      _budgetWidgetSelectedIdsKey,
      jsonEncode(sanitized),
    );
  }

  static List<int> _decodeIntList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map((value) {
            if (value is int) return value;
            if (value is num) return value.toInt();
            if (value is String) return int.tryParse(value.trim());
            return null;
          })
          .whereType<int>()
          .where((id) => id > 0)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static bool _sameIds(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

enum BudgetWidgetSelectionResult {
  added,
  alreadySelected,
  limitReached,
}
