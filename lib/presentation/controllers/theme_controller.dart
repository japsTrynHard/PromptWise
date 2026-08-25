import 'package:flutter/material.dart';

import '../../data/services/storage_service.dart';

class ThemeController extends ChangeNotifier {
  ThemeController({StorageService? storage})
    : _storage = storage ?? StorageService();

  static const _themeKey = 'themeMode';

  final StorageService _storage;
  ThemeMode _themeMode = ThemeMode.light;
  bool _initialized = false;

  ThemeMode get themeMode => _themeMode;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    try {
      await _storage.init();
      final stored = _storage.getString(_themeKey, defaultValue: 'light');
      _themeMode = switch (stored) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      _themeMode = ThemeMode.light;
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();

    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };

    try {
      await _storage.setString(_themeKey, value);
    } catch (_) {
      // Theme changes remain active for the current session.
    }
  }
}
