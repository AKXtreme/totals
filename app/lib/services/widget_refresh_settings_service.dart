import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WidgetRefreshSettingsService {
  WidgetRefreshSettingsService._();

  static final WidgetRefreshSettingsService instance =
      WidgetRefreshSettingsService._();

  static const _kWidgetRefreshHour = 'widget_refresh_hour';
  static const _kWidgetRefreshMinute = 'widget_refresh_minute';

  Future<TimeOfDay> getWidgetRefreshTime() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt(_kWidgetRefreshHour) ?? 0;
    final minute = prefs.getInt(_kWidgetRefreshMinute) ?? 0;
    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> setWidgetRefreshTime(TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kWidgetRefreshHour, time.hour);
    await prefs.setInt(_kWidgetRefreshMinute, time.minute);
  }
}
