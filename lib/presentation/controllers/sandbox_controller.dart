import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../data/models/learning_topic.dart';
import '../../data/models/prompt_coach.dart';
import '../../data/repositories/prompt_coach_repository.dart';
import '../../data/services/integration_service.dart';
import '../../data/services/prompt_coach_rubric_engine.dart';

class SandboxController extends ChangeNotifier {
  SandboxController({
    required IntegrationService? service,
    PromptCoachRepository? repository,
  }) : _service = service,
       _repository = repository;

  static const int minimumPromptLength = 10;
  static const int maximumPromptLength = 1500;

  final IntegrationService? _service;
  final PromptCoachRepository? _repository;

  String? _activeUserId;
  String? _activeSessionId;
  PromptCoachMode _mode = PromptCoachMode.standard;
  String _lastPrompt = '';
  PromptCoachAnalysis? _analysis;
  PromptCoachAnalysis? _previousAnalysis;
  PromptAiGuidance? _aiGuidance;
  PromptCoachUsage _usage = PromptCoachUsage.initial();
  List<PromptCoachSessionSummary> _recentSessions = const [];
  List<PromptPrivacyFinding> _livePrivacyFindings = const [];
  String? _validationMessage;
  String? _serviceMessage;
  String? _historyMessage;
  bool _evaluated = false;
  bool _isLoading = false;
  bool _isHistoryLoading = false;
  bool _coachAvailable = false;
  bool _coachChecked = false;
  int _revisionNumber = 0;
  int _masteryEvidenceCount = 0;

  String? get activeUserId => _activeUserId;
  String? get activeSessionId => _activeSessionId;
  PromptCoachMode get mode => _mode;
  String get lastPrompt => _lastPrompt;
  PromptCoachAnalysis? get analysis => _analysis;
  PromptCoachAnalysis? get previousAnalysis => _previousAnalysis;
  PromptAiGuidance? get aiGuidance => _aiGuidance;
  PromptCoachUsage get usage => _usage;
  List<PromptCoachSessionSummary> get recentSessions =>
      List.unmodifiable(_recentSessions);
  List<PromptPrivacyFinding> get livePrivacyFindings =>
      List.unmodifiable(_livePrivacyFindings);
  String? get validationMessage => _validationMessage;
  String? get serviceMessage => _serviceMessage;
  String? get historyMessage => _historyMessage;
  bool get evaluated => _evaluated;
  bool get isLoading => _isLoading;
  bool get isHistoryLoading => _isHistoryLoading;
  bool get coachAvailable => _coachAvailable;
  bool get coachChecked => _coachChecked;
  int get revisionNumber => _revisionNumber;
  int get masteryEvidenceCount => _masteryEvidenceCount;

  bool get canUseAi =>
      _coachAvailable && !_usage.exhausted && !_livePrivacyBlocksAi;
  bool get _livePrivacyBlocksAi =>
      _livePrivacyFindings.any((finding) => finding.blocksAi);

  int get scoreImprovement {
    final current = _analysis?.scores.overallPercent;
    final previous = _previousAnalysis?.scores.overallPercent;
    if (current == null || previous == null) return 0;
    return current - previous;
  }

  Future<void> bindAuthenticatedUser(String? userId) async {
    if (_activeUserId == userId && _coachChecked) return;
    _activeUserId = userId;
    _activeSessionId = null;
    _recentSessions = const [];
    _historyMessage = null;
    _coachChecked = false;
    _coachAvailable = false;
    _usage = PromptCoachUsage.initial();
    _resetSessionState(notify: false);
    notifyListeners();

    // Prompt Coach data is intentionally lazy. The Coach screen calls init()
    // on first open, so normal sign-in does not spend two network requests on
    // a feature the learner may not use in that session.
    if (userId == null) return;
  }

  Future<void> init() async {
    final requests = <Future<void>>[];
    if (!_coachChecked && !_isLoading) {
      requests.add(checkCoachAvailability());
    }
    if (_activeUserId != null && _recentSessions.isEmpty) {
      requests.add(refreshHistory());
    }
    if (requests.isNotEmpty) {
      await Future.wait(requests);
    }
  }

  Future<void> checkCoachAvailability() async {
    if (_coachChecked && _activeUserId != null) return;
    final service = _service;
    if (service == null) {
      _coachChecked = true;
      _coachAvailable = false;
      _serviceMessage =
          'AI Coach is unavailable. Standard Coach remains fully available.';
      notifyListeners();
      return;
    }

    try {
      final status = await service.getCoachStatus();
      _coachAvailable = status.available;
      _usage = status.usage;
      _serviceMessage = status.available
          ? null
          : 'AI Coach is unavailable. Standard Coach remains fully available.';
    } on TimeoutException {
      _coachAvailable = false;
      _serviceMessage =
          'AI Coach status check timed out. Standard Coach remains available.';
    } on http.ClientException {
      _coachAvailable = false;
      _serviceMessage =
          'You appear to be offline. Standard Coach still works on this device.';
    } on IntegrationException catch (error) {
      _coachAvailable = false;
      _serviceMessage = _friendlyServiceMessage(error.message);
    } catch (_) {
      _coachAvailable = false;
      _serviceMessage =
          'AI Coach is unavailable. Standard Coach remains fully available.';
    } finally {
      _coachChecked = true;
      if (_mode == PromptCoachMode.ai && !canUseAi) {
        _mode = PromptCoachMode.standard;
      }
      notifyListeners();
    }
  }

  Future<void> refreshHistory() async {
    final userId = _activeUserId;
    final repository = _repository;
    if (userId == null || repository == null || _isHistoryLoading) return;

    _isHistoryLoading = true;
    _historyMessage = null;
    notifyListeners();
    try {
      _recentSessions = await repository.fetchRecentSessions();
    } catch (_) {
      _historyMessage =
          'Revision history could not be refreshed. Your current coaching session still works.';
    } finally {
      _isHistoryLoading = false;
      notifyListeners();
    }
  }

  Future<List<PromptCoachRevision>> fetchSessionRevisions(
    String sessionId,
  ) async {
    final userId = _activeUserId;
    final repository = _repository;
    if (userId == null || repository == null) return const [];
    return repository.fetchSessionRevisions(
      userId: userId,
      sessionId: sessionId,
    );
  }


  void setMode(PromptCoachMode value) {
    if (value == PromptCoachMode.ai && !canUseAi) {
      _serviceMessage = _usage.exhausted
          ? 'You have used all ${_usage.limit} AI Coach reviews for today. Standard Coach is unlimited.'
          : _livePrivacyBlocksAi
          ? 'Remove the detected private information before using AI Coach.'
          : 'AI Coach is unavailable right now. Standard Coach is unlimited.';
      notifyListeners();
      return;
    }
    if (_mode == value) return;
    _mode = value;
    _serviceMessage = null;
    notifyListeners();
  }

  void inspectPrompt(String prompt) {
    final findings = PromptCoachRubricEngine.inspectPrivacy(prompt.trim());
    if (listEquals(findings.map((e) => e.code).toList(),
        _livePrivacyFindings.map((e) => e.code).toList())) {
      return;
    }
    _livePrivacyFindings = findings;
    if (_mode == PromptCoachMode.ai && _livePrivacyBlocksAi) {
      _serviceMessage =
          'AI Coach is paused because this prompt may contain private information.';
    }
    notifyListeners();
  }

  Future<bool> reviewPrompt(
    String prompt, {
    required Map<String, int> masteryContext,
    required String learnerRank,
    LearningTopic? focusTopic,
  }) async {
    final cleanedPrompt = prompt.trim();
    final validationError = validatePrompt(cleanedPrompt);

    if (validationError != null) {
      _validationMessage = validationError;
      _evaluated = false;
      notifyListeners();
      return false;
    }

    _validationMessage = null;
    _lastPrompt = cleanedPrompt;
    _isLoading = true;
    _serviceMessage = null;
    _masteryEvidenceCount = 0;
    notifyListeners();

    final standardAnalysis = PromptCoachRubricEngine.analyze(cleanedPrompt);
    _livePrivacyFindings = standardAnalysis.privacyFindings;
    PromptAiGuidance? aiGuidance;
    var effectiveMode = _mode;

    if (_mode == PromptCoachMode.ai) {
      if (standardAnalysis.blocksAi) {
        effectiveMode = PromptCoachMode.standard;
        _serviceMessage =
            'Private information was detected, so this prompt was not sent to AI Coach. Standard feedback is shown instead.';
      } else if (_usage.exhausted) {
        effectiveMode = PromptCoachMode.standard;
        _serviceMessage =
            'Your daily AI Coach limit is reached. Standard feedback is shown instead.';
      } else {
        final service = _service;
        if (service == null) {
          effectiveMode = PromptCoachMode.standard;
          _serviceMessage =
              'AI Coach is unavailable. Standard feedback is shown instead.';
        } else {
          try {
            final result = await service.getPromptGuidance(
              prompt: cleanedPrompt,
              standardAnalysis: standardAnalysis,
              masteryContext: masteryContext,
              learnerRank: learnerRank,
            );
            aiGuidance = result.guidance;
            _usage = result.usage;
            _coachAvailable = true;
            _coachChecked = true;
          } on TimeoutException {
            effectiveMode = PromptCoachMode.standard;
            _serviceMessage =
                'AI Coach took too long to respond. Standard feedback is shown instead.';
          } on http.ClientException {
            effectiveMode = PromptCoachMode.standard;
            _serviceMessage =
                'You appear to be offline. Standard feedback is shown instead.';
          } on IntegrationException catch (error) {
            effectiveMode = PromptCoachMode.standard;
            _serviceMessage = _friendlyServiceMessage(error.message);
            if (error.message.toLowerCase().contains('daily')) {
              _usage = PromptCoachUsage(
                used: _usage.limit,
                limit: _usage.limit,
                resetAt: _usage.resetAt,
              );
            }
          } catch (_) {
            effectiveMode = PromptCoachMode.standard;
            _serviceMessage =
                'AI Coach is unavailable. Standard feedback is shown instead.';
          }
        }
      }
    }

    final before = _analysis;
    _previousAnalysis = before;
    _analysis = standardAnalysis;
    _aiGuidance = aiGuidance;
    _evaluated = true;

    final repository = _repository;
    final userId = _activeUserId;
    if (repository != null && userId != null) {
      try {
        final saved = await repository.recordRevision(
          sessionId: _activeSessionId,
          prompt: cleanedPrompt,
          mode: effectiveMode,
          analysis: standardAnalysis,
          aiGuidance: aiGuidance,
          focusTopic: focusTopic,
        );
        _activeSessionId = saved.sessionId;
        _revisionNumber = saved.revisionNumber;
        _masteryEvidenceCount = saved.masteryEvidenceCount;
        await refreshHistory();
      } catch (_) {
        _historyMessage =
            'Feedback is ready, but this revision could not be synced to your history.';
      }
    } else {
      _revisionNumber += 1;
    }

    _isLoading = false;
    notifyListeners();
    return true;
  }

  String? validatePrompt(String prompt) {
    if (prompt.isEmpty) {
      return 'Enter a prompt before requesting feedback.';
    }
    if (prompt.length < minimumPromptLength) {
      return 'Add more detail. The prompt must contain at least $minimumPromptLength characters.';
    }
    if (prompt.length > maximumPromptLength) {
      return 'The prompt is too long. Keep it within $maximumPromptLength characters.';
    }
    return null;
  }

  void clearValidationMessage() {
    if (_validationMessage == null) return;
    _validationMessage = null;
    notifyListeners();
  }

  void startNewSession() {
    _activeSessionId = null;
    _resetSessionState(notify: true);
  }

  void _resetSessionState({required bool notify}) {
    _lastPrompt = '';
    _analysis = null;
    _previousAnalysis = null;
    _aiGuidance = null;
    _livePrivacyFindings = const [];
    _validationMessage = null;
    _serviceMessage = null;
    _evaluated = false;
    _isLoading = false;
    _revisionNumber = 0;
    _masteryEvidenceCount = 0;
    if (notify) notifyListeners();
  }

  String _friendlyServiceMessage(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('daily') || lower.contains('limit')) {
      return 'Your daily AI Coach limit is reached. Standard Coach remains unlimited.';
    }
    if (lower.contains('private') || lower.contains('sensitive')) {
      return 'Remove private information before using AI Coach. Standard Coach can still review the prompt locally.';
    }
    if (lower.contains('rate') || lower.contains('too many')) {
      return 'AI Coach is busy right now. Standard feedback is shown instead.';
    }
    if (lower.contains('key') || lower.contains('configured')) {
      return 'AI Coach is unavailable. Standard feedback is shown instead.';
    }
    if (lower.contains('timeout') || lower.contains('connection')) {
      return 'You appear to be offline. Standard feedback is shown instead.';
    }
    return 'AI Coach is unavailable. Standard feedback is shown instead.';
  }
}
