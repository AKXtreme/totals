import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  static const String _uiScaleKey = 'ui_scale';
  static const List<double> _uiScaleOptions = <double>[
    0.5,
    0.6,
    0.7,
    0.75,
    0.8,
    0.85,
    0.9,
    0.95,
    1.0,
  ];
  ThemeMode _themeMode = ThemeMode.light;
  double _uiScale = 1.0;

  ThemeMode get themeMode => _themeMode;
  double get uiScale => _uiScale;
  List<double> get availableUiScales => List<double>.unmodifiable(_uiScaleOptions);
  String get uiScaleLabel => _formatUiScale(_uiScale);
  bool get isZoomedOut => (_uiScale - 0.75).abs() < 0.001;

  ThemeProvider() {
    _loadThemeMode();
    _loadUiScale();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString(_themeKey);
    if (savedTheme != null) {
      _themeMode = ThemeMode.values.firstWhere(
        (mode) => mode.toString() == savedTheme,
        orElse: () => ThemeMode.light,
      );
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    // Defer notification to the next frame so any in-progress build/animation
    // (e.g. overlay entries from bottom sheets) finishes first. This prevents
    // InheritedElement ancestor-chain assertions during heavy tree rebuilds.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.toString());
  }

  Future<void> _loadUiScale() async {
    final prefs = await SharedPreferences.getInstance();
    final savedScale = prefs.getDouble(_uiScaleKey);
    if (savedScale != null) {
      _uiScale = _normalizeUiScale(savedScale);
      notifyListeners();
    }
  }

  Future<void> setUiScale(double scale) async {
    final normalized = _normalizeUiScale(scale);
    _uiScale = normalized;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_uiScaleKey, normalized);
  }

  Future<void> setZoomedOut(bool value) async {
    await setUiScale(value ? 0.75 : 1.0);
  }

  double _normalizeUiScale(double value) {
    if (value <= 0) return 1.0;
    double nearest = _uiScaleOptions.first;
    double nearestDelta = (value - nearest).abs();
    for (final option in _uiScaleOptions.skip(1)) {
      final delta = (value - option).abs();
      if (delta < nearestDelta) {
        nearest = option;
        nearestDelta = delta;
      }
    }
    return nearest;
  }

  String _formatUiScale(double value) {
    final formatted = value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    return '${formatted}x';
  }

  void toggleTheme() {
    if (_themeMode == ThemeMode.light) {
      setThemeMode(ThemeMode.dark);
    } else {
      setThemeMode(ThemeMode.light);
    }
  }
}

