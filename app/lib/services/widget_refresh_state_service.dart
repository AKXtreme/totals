import 'package:shared_preferences/shared_preferences.dart';

class WidgetRefreshStateService {
  WidgetRefreshStateService._();

  static final WidgetRefreshStateService instance =
      WidgetRefreshStateService._();

  static const _kWidgetLastRefreshEpochMs = 'widget_last_refresh_epoch_ms';

  Future<DateTime?> getLastRefreshAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(_kWidgetLastRefreshEpochMs);
    if (raw == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<void> setLastRefreshAt(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kWidgetLastRefreshEpochMs, time.millisecondsSinceEpoch);
  }

  Future<void> clearLastRefreshAt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kWidgetLastRefreshEpochMs);
  }
}
