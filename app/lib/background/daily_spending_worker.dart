import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:workmanager/workmanager.dart';
import 'package:totals/services/notification_service.dart';
import 'package:totals/services/notification_settings_service.dart';
import 'package:totals/services/widget_service.dart';
import 'package:totals/services/widget_data_provider.dart';
import 'package:totals/services/widget_refresh_settings_service.dart';
import 'package:totals/services/widget_refresh_state_service.dart';

const String dailySpendingSummaryTask = 'dailySpendingSummary';
const String dailySpendingSummaryUniqueName = 'dailySpendingSummaryUnique';
const String widgetMidnightRefreshTask = 'widgetMidnightRefresh';
const String widgetMidnightRefreshUniqueName = 'widgetMidnightRefreshUnique';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();

      if (task == widgetMidnightRefreshTask) {
        await WidgetService.initialize();
        final now = DateTime.now();
        final scheduledTime =
            await WidgetRefreshSettingsService.instance.getWidgetRefreshTime();
        final lastRefresh =
            await WidgetRefreshStateService.instance.getLastRefreshAt();
        if (!_isAfterOrEqualTimeOfDay(now, scheduledTime)) {
          return true;
        }
        if (lastRefresh != null && _isSameDay(lastRefresh, now)) {
          return true;
        }
        await WidgetService.refreshWidget();
        return true;
      }

      if (task != dailySpendingSummaryTask) return true;

      final settings = NotificationSettingsService.instance;

      final enabled = await settings.isDailySummaryEnabled();
      if (!enabled) return true;

      final now = DateTime.now();

      final scheduledTime = await settings.getDailySummaryTime();
      if (!_isAfterOrEqualTimeOfDay(now, scheduledTime)) return true;

      final lastSent = await settings.getDailySummaryLastSentAt();
      if (lastSent != null && _isSameDay(lastSent, now)) return true;

      final totalSpent = await WidgetDataProvider().getTodaySpending();
      final shown = await NotificationService.instance.showDailySpendingNotification(
        amount: totalSpent,
      );

      if (shown) {
        await settings.setDailySummaryLastSentAt(now);
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('debug: Daily spending worker failed: $e');
      }
      return true;
    }
  });
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool _isAfterOrEqualTimeOfDay(DateTime now, TimeOfDay time) {
  if (now.hour > time.hour) return true;
  if (now.hour < time.hour) return false;
  return now.minute >= time.minute;
}
