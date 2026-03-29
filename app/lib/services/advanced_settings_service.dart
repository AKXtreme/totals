import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ProfileDoubleTapAction {
  lock,
  doNothing,
}

class AdvancedSettingsService {
  AdvancedSettingsService._();

  static final AdvancedSettingsService instance = AdvancedSettingsService._();

  static const String _profileDoubleTapActionKey =
      'redesign_profile_double_tap_action';

  final ValueNotifier<ProfileDoubleTapAction> profileDoubleTapAction =
      ValueNotifier<ProfileDoubleTapAction>(ProfileDoubleTapAction.lock);

  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileDoubleTapActionKey);
    profileDoubleTapAction.value = _fromStorage(raw);
    _loaded = true;
  }

  Future<void> setProfileDoubleTapAction(ProfileDoubleTapAction action) async {
    await ensureLoaded();
    if (profileDoubleTapAction.value == action) return;
    profileDoubleTapAction.value = action;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileDoubleTapActionKey, _toStorage(action));
  }

  static ProfileDoubleTapAction _fromStorage(String? raw) {
    switch (raw) {
      case 'do_nothing':
        return ProfileDoubleTapAction.doNothing;
      case 'lock':
      default:
        return ProfileDoubleTapAction.lock;
    }
  }

  static String _toStorage(ProfileDoubleTapAction action) {
    switch (action) {
      case ProfileDoubleTapAction.lock:
        return 'lock';
      case ProfileDoubleTapAction.doNothing:
        return 'do_nothing';
    }
  }
}
