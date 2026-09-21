import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../data/models/learning_survey.dart';
import '../../data/repositories/learning_survey_repository.dart';

class LearningSurveyController extends ChangeNotifier {
  final LearningSurveyGateway _repository;
  LearningSurveyController({required LearningSurveyGateway repository})
      : _repository = repository;

  String? _userId;
  LearningSurvey? _survey;
  bool _loading = false;
  bool _loaded = false;
  bool _saving = false;
  String? _error;
  int _generation = 0;
  bool _disposed = false;

  LearningSurvey? get survey => _survey;
  bool get isLoading => _loading;
  bool get isSaving => _saving;
  String? get errorMessage => _error;
  bool isReadyFor(String? userId) =>
      userId != null && _userId == userId && _loaded && !_loading;

  void _changed() => scheduleMicrotask(() {
        if (!_disposed) notifyListeners();
      });

  Future<void> bindUser(String? userId) async {
    if (_disposed || _userId == userId) return;
    final generation = ++_generation;
    _userId = userId;
    _survey = null; // Prevent preferences leaking across accounts.
    _loading = userId != null;
    _loaded = userId == null;
    _saving = false;
    _error = null;
    _changed();
    if (userId == null) return;
    try {
      final survey = await _repository.fetch(userId);
      if (_disposed || generation != _generation) return;
      _survey = survey;
      _loaded = true;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _error = 'Could not load your learning preferences. Retry when connected.';
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
    _userId = null;
    await bindUser(userId);
  }

  Future<bool> submit(LearningSurvey survey) async {
    final userId = _userId;
    if (_disposed || userId == null || !_loaded || _saving) return false;
    final generation = _generation;
    try {
      survey.validate();
    } on ArgumentError catch (error) {
      _error = error.message?.toString() ?? 'Check your survey answers.';
      _changed();
      return false;
    }
    _saving = true;
    _error = null;
    _changed();
    try {
      final saved = await _repository.save(userId, survey);
      if (_disposed || generation != _generation) return false;
      _survey = saved;
      return true;
    } catch (_) {
      if (_disposed || generation != _generation) return false;
      _error = 'Could not save your answers. Please retry.';
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
