import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/dictionary_entry.dart';
import '../services/dictionary_service.dart';
import '../services/storage_service.dart';

class DictionaryController extends ChangeNotifier {
  DictionaryController({DictionaryService? service, StorageService? storage})
    : _service = service ?? DictionaryService(),
      _storage = storage ?? StorageService();

  static const _cacheKey = 'lessonDictionaryCacheV1';
  static const _cacheLimit = 12;

  final DictionaryService _service;
  final StorageService _storage;

  DictionaryEntry? _entry;
  bool _isLoading = false;
  bool _hasSearched = false;
  bool _showingSavedDefinition = false;
  String? _message;
  String _lastWord = '';

  DictionaryEntry? get entry => _entry;
  bool get isLoading => _isLoading;
  bool get hasSearched => _hasSearched;
  bool get showingSavedDefinition => _showingSavedDefinition;
  String? get message => _message;
  String get lastWord => _lastWord;

  Future<void> lookup(String word) async {
    final cleaned = word.trim();
    if (cleaned.isEmpty) {
      _entry = null;
      _hasSearched = false;
      _message = 'Type a word from the lesson first.';
      notifyListeners();
      return;
    }
    if (cleaned.length > 50) {
      _entry = null;
      _hasSearched = false;
      _message = 'Try one short word at a time.';
      notifyListeners();
      return;
    }

    _lastWord = cleaned.toLowerCase();
    _isLoading = true;
    _hasSearched = true;
    _showingSavedDefinition = false;
    _message = null;
    notifyListeners();

    try {
      final result = await _service.lookup(_lastWord);
      _entry = result;
      _showingSavedDefinition = false;
      _message = null;
      await _saveToCache(result);
    } on DictionaryNotFoundException catch (error) {
      _entry = null;
      _showingSavedDefinition = false;
      _message = error.message;
    } on TimeoutException {
      await _useSavedDefinition(
        'The connection is taking too long. Check your internet and try again.',
      );
    } on http.ClientException {
      await _useSavedDefinition(
        'You are offline. Connect to the internet to look up a new word.',
      );
    } on DictionaryServiceException catch (error) {
      await _useSavedDefinition(error.message);
    } catch (_) {
      await _useSavedDefinition(
        'The meaning could not be loaded right now. Please try again.',
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> retry() async {
    if (_lastWord.isEmpty || _isLoading) return;
    await lookup(_lastWord);
  }

  void clear() {
    _entry = null;
    _isLoading = false;
    _hasSearched = false;
    _showingSavedDefinition = false;
    _message = null;
    _lastWord = '';
    notifyListeners();
  }

  Future<void> _saveToCache(DictionaryEntry result) async {
    try {
      await _storage.init();
      final cache = _readCacheMap();
      cache.remove(result.word.toLowerCase());
      cache[result.word.toLowerCase()] = result.toMap();
      while (cache.length > _cacheLimit) {
        cache.remove(cache.keys.first);
      }
      await _storage.setString(_cacheKey, jsonEncode(cache));
    } catch (_) {
      // A cache failure must not hide an online definition.
    }
  }

  Future<void> _useSavedDefinition(String fallbackMessage) async {
    try {
      await _storage.init();
      final cache = _readCacheMap();
      final raw = cache[_lastWord.toLowerCase()];
      if (raw is Map) {
        _entry = DictionaryEntry.fromMap(Map<String, dynamic>.from(raw));
        _showingSavedDefinition = true;
        _message = 'You are offline. Showing the saved meaning for this word.';
        return;
      }
    } catch (_) {
      // Fall through to the original friendly message.
    }
    _entry = null;
    _showingSavedDefinition = false;
    _message = fallbackMessage;
  }

  Map<String, dynamic> _readCacheMap() {
    final raw = _storage.getString(_cacheKey);
    if (raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // Ignore broken cache data.
    }
    return <String, dynamic>{};
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
