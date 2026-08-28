import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/models/dictionary_entry.dart';
import '../../data/services/dictionary_service.dart';
import '../../data/services/storage_service.dart';

class DictionaryController extends ChangeNotifier {
  DictionaryController({
    DictionaryLookupService? service,
    StorageService? storage,
  }) : _service = service ?? DictionaryService(),
       _storage = storage ?? StorageService();

  static const _cacheKey = 'lessonDictionaryCacheV2';
  static const _cacheLimit = 12;

  final DictionaryLookupService _service;
  final StorageService _storage;

  DictionaryEntry? _entry;
  bool _isLoading = false;
  bool _hasSearched = false;
  bool _showingSavedDefinition = false;
  String? _message;
  String _lastWord = '';
  int _generation = 0;
  bool _disposed = false;
  String? _activeWord;
  Future<void>? _activeLookup;

  DictionaryEntry? get entry => _entry;
  bool get isLoading => _isLoading;
  bool get hasSearched => _hasSearched;
  bool get showingSavedDefinition => _showingSavedDefinition;
  String? get message => _message;
  String get lastWord => _lastWord;

  Future<void> lookup(String word, {bool forceOnline = false}) {
    final cleaned = word.trim();
    if (cleaned.isEmpty) {
      _entry = null;
      _hasSearched = false;
      _message = 'Type a word from the lesson first.';
      _notify();
      return Future<void>.value();
    }
    if (cleaned.length > 50) {
      _entry = null;
      _hasSearched = false;
      _message = 'Try one short word at a time.';
      _notify();
      return Future<void>.value();
    }

    final normalized = cleaned.toLowerCase();
    if (_isLoading && _activeWord == normalized) {
      return _activeLookup ?? Future<void>.value();
    }

    final generation = ++_generation;
    _activeWord = normalized;
    late final Future<void> operation;
    operation =
        _lookupInternal(
          normalized,
          forceOnline: forceOnline,
          generation: generation,
        ).whenComplete(() {
          if (identical(_activeLookup, operation)) {
            _activeLookup = null;
            _activeWord = null;
          }
        });
    _activeLookup = operation;
    return operation;
  }

  Future<void> _lookupInternal(
    String normalized, {
    required bool forceOnline,
    required int generation,
  }) async {
    _lastWord = normalized;
    _isLoading = true;
    _hasSearched = true;
    _showingSavedDefinition = false;
    _message = null;
    _notify();

    if (!forceOnline) {
      final saved = await _readSavedDefinition(normalized, touch: true);
      if (!_isCurrent(generation)) return;
      if (saved != null) {
        _entry = saved;
        _showingSavedDefinition = true;
        _isLoading = false;
        _notify();
        return;
      }
    }

    try {
      final result = await _service.lookup(normalized);
      if (!_isCurrent(generation)) return;
      _entry = result;
      _showingSavedDefinition = false;
      _message = null;
      await _saveToCache(result);
    } on DictionaryNotFoundException catch (error) {
      if (!_isCurrent(generation)) return;
      _entry = null;
      _showingSavedDefinition = false;
      _message = error.message;
    } on TimeoutException catch (error, stackTrace) {
      _debugFailure(error, stackTrace);
      if (!_isCurrent(generation)) return;
      await _useSavedDefinition(
        normalized,
        'The connection is taking too long. Please try again.',
      );
    } on DictionaryServiceException catch (error, stackTrace) {
      _debugFailure(error, stackTrace);
      if (!_isCurrent(generation)) return;
      await _useSavedDefinition(normalized, error.message);
    } catch (error, stackTrace) {
      _debugFailure(error, stackTrace);
      if (!_isCurrent(generation)) return;
      await _useSavedDefinition(
        normalized,
        'The meaning could not be loaded right now. Please try again.',
      );
    } finally {
      if (_isCurrent(generation)) {
        _isLoading = false;
        _notify();
      }
    }
  }

  Future<void> retry() async {
    if (_lastWord.isEmpty || _isLoading) return;
    await lookup(_lastWord, forceOnline: true);
  }

  void clear() {
    _generation++;
    _entry = null;
    _isLoading = false;
    _hasSearched = false;
    _showingSavedDefinition = false;
    _message = null;
    _lastWord = '';
    _notify();
  }

  Future<void> _saveToCache(DictionaryEntry result) async {
    try {
      await _storage.init();
      final cache = _readCacheMap();
      final key = result.word.toLowerCase();
      cache.remove(key);
      cache[key] = result.toMap();
      while (cache.length > _cacheLimit) {
        cache.remove(cache.keys.first);
      }
      await _storage.setString(_cacheKey, jsonEncode(cache));
    } catch (error, stackTrace) {
      _debugFailure(error, stackTrace, label: 'Dictionary cache write');
    }
  }

  Future<DictionaryEntry?> _readSavedDefinition(
    String word, {
    bool touch = false,
  }) async {
    try {
      await _storage.init();
      final cache = _readCacheMap();
      final key = word.toLowerCase();
      final raw = cache[key];
      if (raw is Map) {
        final entry = DictionaryEntry.fromMap(Map<String, dynamic>.from(raw));
        if (entry.word.isEmpty || entry.definitions.isEmpty) return null;
        if (touch) {
          cache.remove(key);
          cache[key] = entry.toMap();
          await _storage.setString(_cacheKey, jsonEncode(cache));
        }
        return entry;
      }
    } catch (error, stackTrace) {
      _debugFailure(error, stackTrace, label: 'Dictionary cache read');
    }
    return null;
  }

  Future<void> _useSavedDefinition(String word, String fallbackMessage) async {
    final saved = await _readSavedDefinition(word, touch: true);
    if (saved != null) {
      _entry = saved;
      _showingSavedDefinition = true;
      _message = 'Showing the saved meaning because live lookup failed.';
      return;
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
      // A corrupt optional cache is ignored and replaced by future results.
    }
    return <String, dynamic>{};
  }

  bool _isCurrent(int generation) => !_disposed && _generation == generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _debugFailure(
    Object error,
    StackTrace stackTrace, {
    String label = 'Dictionary lookup',
  }) {
    if (kDebugMode) debugPrint('$label failed: $error\n$stackTrace');
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
