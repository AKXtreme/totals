import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum HomeAppBarAction {
  quickCash,
  notifications,
}

class AdvancedSettingsService {
  AdvancedSettingsService._();

  static final AdvancedSettingsService instance = AdvancedSettingsService._();

  static const String _homeAppBarActionKey = 'redesign_home_appbar_action';

  final ValueNotifier<HomeAppBarAction> homeAppBarAction =
      ValueNotifier<HomeAppBarAction>(HomeAppBarAction.notifications);

  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_homeAppBarActionKey);
    homeAppBarAction.value = _fromStorage(raw);
    _loaded = true;
  }

  Future<void> setHomeAppBarAction(HomeAppBarAction action) async {
    await ensureLoaded();
    if (homeAppBarAction.value == action) return;
    homeAppBarAction.value = action;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_homeAppBarActionKey, _toStorage(action));
  }

  static HomeAppBarAction _fromStorage(String? raw) {
    switch (raw) {
      case 'quick_cash':
        return HomeAppBarAction.quickCash;
      case 'notifications':
      default:
        return HomeAppBarAction.notifications;
    }
  }

  static String _toStorage(HomeAppBarAction action) {
    switch (action) {
      case HomeAppBarAction.quickCash:
        return 'quick_cash';
      case HomeAppBarAction.notifications:
        return 'notifications';
    }
  }
}
