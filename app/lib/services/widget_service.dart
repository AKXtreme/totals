import 'dart:convert';

import 'package:home_widget/home_widget.dart';
import 'package:totals/services/widget_data_provider.dart';
import 'package:totals/services/widget_refresh_state_service.dart';

class WidgetService {
  static const String appGroupId = 'group.com.example.totals.widget';
  static const String androidWidgetName = 'ExpenseWidgetProvider';
  static const String androidWidgetQualifiedName =
      'com.example.offline_gateway.$androidWidgetName';

  static WidgetDataProvider? _dataProvider;

  static WidgetDataProvider get dataProvider {
    _dataProvider ??= WidgetDataProvider();
    return _dataProvider!;
  }

  /// Initialize the widget plugin
  static Future<void> initialize() async {
    await HomeWidget.setAppGroupId(appGroupId);
  }

  /// Refresh widget with current data
  static Future<void> refreshWidget() async {
    try {
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
          'expense_total_raw', todaySpending.toString());
      await HomeWidget.saveWidgetData<String>(
          'expense_last_updated', lastUpdated);

      final categoryJson =
          jsonEncode(categories.map((c) => c.toJson()).toList());
      await HomeWidget.saveWidgetData<String>(
          'expense_categories', categoryJson);

      await HomeWidget.saveWidgetData<String>('income_total', formattedIncome);
      await HomeWidget.saveWidgetData<String>(
          'income_total_raw', todayIncome.toString());
      await HomeWidget.saveWidgetData<String>(
          'income_last_updated', lastUpdated);

      final incomeCategoryJson =
          jsonEncode(incomeCategories.map((c) => c.toJson()).toList());
      await HomeWidget.saveWidgetData<String>(
          'income_categories', incomeCategoryJson);

      await _saveCategoryData(
        prefix: 'category',
        categories: categories,
      );
      await _saveCategoryData(
        prefix: 'income_category',
        categories: incomeCategories,
      );
      await HomeWidget.updateWidget(androidName: androidWidgetName);
      await WidgetRefreshStateService.instance.setLastRefreshAt(DateTime.now());

      print(
        'Widget updated: $formattedAmount / $formattedIncome at $lastUpdated',
      );
    } catch (e) {
      print('Error updating widget: $e');
    }
  }

  static Future<void> _saveCategoryData({
    required String prefix,
    required List<CategoryExpense> categories,
  }) async {
    for (int i = 0; i < 3; i++) {
      if (i < categories.length) {
        final cat = categories[i];
        await HomeWidget.saveWidgetData<String>(
            '${prefix}_${i}_name', cat.name);
        await HomeWidget.saveWidgetData<String>(
            '${prefix}_${i}_amount',
            dataProvider.formatAmountForWidget(cat.amount));
        await HomeWidget.saveWidgetData<String>(
            '${prefix}_${i}_amount_raw', cat.amount.toString());
        await HomeWidget.saveWidgetData<String>(
            '${prefix}_${i}_color', cat.colorHex);
      } else {
        await HomeWidget.saveWidgetData<String>('${prefix}_${i}_name', '');
        await HomeWidget.saveWidgetData<String>('${prefix}_${i}_amount', '');
        await HomeWidget.saveWidgetData<String>(
            '${prefix}_${i}_amount_raw', '0');
        await HomeWidget.saveWidgetData<String>('${prefix}_${i}_color', '');
      }
    }
  }

  /// Send basic data to the widget
  static Future<void> updateWidgetData({
    required String totalAmount,
    required String lastUpdated,
  }) async {
    await HomeWidget.saveWidgetData<String>('expense_total', totalAmount);
    await HomeWidget.saveWidgetData<String>('expense_last_updated', lastUpdated);
    await HomeWidget.updateWidget(
      qualifiedAndroidName: androidWidgetQualifiedName,
    );
    await WidgetRefreshStateService.instance.setLastRefreshAt(DateTime.now());
  }
}
