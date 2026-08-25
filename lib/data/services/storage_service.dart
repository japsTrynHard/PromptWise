import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  SharedPreferences? _prefs;

  bool get isInitialized => _prefs != null;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  SharedPreferences get _instance {
    final prefs = _prefs;
    if (prefs == null) {
      throw StateError('StorageService.init() must be called before reading.');
    }
    return prefs;
  }

  int getInt(String key, {int defaultValue = 0}) =>
      _instance.getInt(key) ?? defaultValue;

  Future<void> setInt(String key, int value) async {
    await init();
    await _instance.setInt(key, value);
  }

  List<String> getStringList(String key) =>
      _instance.getStringList(key) ?? const [];

  Future<void> setStringList(String key, List<String> value) async {
    await init();
    await _instance.setStringList(key, value);
  }

  String getString(String key, {String defaultValue = ''}) =>
      _instance.getString(key) ?? defaultValue;

  Future<void> setString(String key, String value) async {
    await init();
    await _instance.setString(key, value);
  }

  Map<String, int> getIntMap(String key) {
    final encoded = getString(key);
    if (encoded.isEmpty) return const {};

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return const {};

      final result = <String, int>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is int) {
          result[entry.key] = value;
        } else if (value is num) {
          result[entry.key] = value.toInt();
        }
      }
      return result;
    } on FormatException {
      return const {};
    }
  }

  Future<void> setIntMap(String key, Map<String, int> value) async {
    await setString(key, jsonEncode(value));
  }

  Future<void> remove(String key) async {
    await init();
    await _instance.remove(key);
  }
}
