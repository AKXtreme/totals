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
      final snapshots = await budgetDataProvider.getAllPeriodSnapshots();

      for (final period in BudgetWidgetDataProvider.supportedPeriods) {
        final snapshot = snapshots[period];
        if (snapshot == null) continue;

        final prefix = 'budget_${snapshot.period}';

        await HomeWidget.saveWidgetData<String>(
          '${prefix}_period_label',
          snapshot.periodLabel,
        );
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_is_empty',
          snapshot.isEmpty ? '1' : '0',
        );
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_empty_message',
          snapshot.emptyMessage,
        );
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_assigned_label',
          snapshot.assignedLabel,
        );
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_activity_label',
          snapshot.activityLabel,
        );
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_available_label',
          snapshot.availableLabel,
        );
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_assigned_raw',
          snapshot.assignedRaw.toString(),
        );
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_activity_raw',
          snapshot.activityRaw.toString(),
        );
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_available_raw',
          snapshot.availableRaw.toString(),
        );
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_needs_available_label',
          snapshot.needsAvailableLabel,
        );
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_wants_available_label',
          snapshot.wantsAvailableLabel,
        );
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_needs_available_raw',
          snapshot.needsAvailableRaw.toString(),
        );
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_wants_available_raw',
          snapshot.wantsAvailableRaw.toString(),
        );
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_percent',
          snapshot.percentUsed.toString(),
        );
        await HomeWidget.saveWidgetData<String>(
          '${prefix}_updated_at',
          snapshot.lastUpdated,
        );
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
}
