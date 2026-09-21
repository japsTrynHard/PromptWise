import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/onboarding_repository.dart';

class OnboardingController extends ChangeNotifier {
  final OnboardingGateway _repository;

  OnboardingController({required OnboardingGateway repository})
      : _repository = repository;

  String? _userId;
  OrientationRecord? _record;
  bool _loading = false;
  bool _loaded = false;
  bool _saving = false;
  String? _error;
  int _generation = 0;
  bool _disposed = false;

  String? get activeUserId => _userId;
  bool get isLoading => _loading;
  bool get isSaving => _saving;
  String? get errorMessage => _error;
  bool get orientationComplete => _record?.isComplete ?? false;
  bool get videoWatched => _record?.videoWatched ?? false;
  bool get surveyReady => _record?.surveyReady ?? false;

  bool isReadyFor(String? userId) =>
      userId != null && _userId == userId && _loaded && !_loading;

  // Used by a ProxyProvider update. Notify asynchronously so it never marks
  // descendants dirty during the ancestor's build.
  void _changed() {
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> bindUser(String? userId) async {
    if (_disposed || _userId == userId) return;
    final generation = ++_generation;
    _userId = userId;
    _record = null;
    _loaded = userId == null;
    _loading = userId != null;
    _saving = false;
    _error = null;
    _changed();
    if (userId == null) return;
    try {
      final record = await _repository.fetch(userId);
      if (_disposed || generation != _generation) return;
      _record = record;
      _loaded = true;
      _error = null;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _error = 'Could not load orientation progress. Check your connection and retry.';
      _loaded = false;
    } finally {
      if (!_disposed && generation == _generation) {
        _loading = false;
        _changed();
      }
    }
  }

  Future<void> retry() async {
    final userId = _userId;
    if (userId == null || _disposed) return;
    // Force a new fetch even when account ID is unchanged.
    _userId = null;
    await bindUser(userId);
  }

  Future<bool> completeOrientation({required bool watched}) async {
    final userId = _userId;
    if (_disposed || userId == null || _loading || _saving || !_loaded) {
      return false;
    }
    final generation = _generation;
    _saving = true;
    _error = null;
    _changed();
    try {
      final record = await _repository.complete(userId, watched: watched);
      if (_disposed || generation != _generation) return false;
      _record = record;
      return record.isComplete;
    } catch (_) {
      if (_disposed || generation != _generation) return false;
      _error = 'Could not save your orientation. Please retry.';
      return false;
    } finally {
      if (!_disposed && generation == _generation) {
        _saving = false;
        _changed();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
