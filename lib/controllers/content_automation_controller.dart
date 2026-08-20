import 'package:flutter/foundation.dart';

import '../models/content_automation.dart';
import '../repositories/content_automation_repository.dart';

class ContentAutomationController extends ChangeNotifier {
  final ContentAutomationRepository? _repository;

  ContentAutomationController({ContentAutomationRepository? repository})
      : _repository = repository;

  bool _isAdministrator = false;
  bool _isLoading = false;
  bool _isMutating = false;
  bool _hasLoaded = false;
  String? _errorMessage;
  String? _successMessage;
  List<ContentSource> _sources = const [];
  List<GeneratedContentDraft> _drafts = const [];
  List<LearningContentHealth> _health = const [];
  List<QuestionBankReviewItem> _questionReviewQueue = const [];
  List<QuestionBankReviewItem> _approvedQuestions = const [];
  AutomationSettings _settings = AutomationSettings.defaults();
  QueueLifecycleStats _queueHealth = QueueLifecycleStats.empty();

  bool get isLoading => _isLoading;
  bool get isMutating => _isMutating;
  bool get hasLoaded => _hasLoaded;
  bool get isAdministrator => _isAdministrator;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;
  List<ContentSource> get sources => List.unmodifiable(_sources);
  List<GeneratedContentDraft> get drafts => List.unmodifiable(_drafts);
  List<LearningContentHealth> get health => List.unmodifiable(_health);
  List<QuestionBankReviewItem> get questionReviewQueue =>
      List.unmodifiable(_questionReviewQueue);
  List<QuestionBankReviewItem> get approvedQuestions =>
      List.unmodifiable(_approvedQuestions);
  AutomationSettings get settings => _settings;
  QueueLifecycleStats get queueHealth => _queueHealth;

  Future<void> bindAdministrator(bool isAdministrator) async {
    final roleChanged = _isAdministrator != isAdministrator;
    _isAdministrator = isAdministrator;

    if (!isAdministrator) {
      _sources = const [];
      _drafts = const [];
      _health = const [];
      _questionReviewQueue = const [];
      _approvedQuestions = const [];
      _settings = AutomationSettings.defaults();
      _queueHealth = QueueLifecycleStats.empty();
      _errorMessage = null;
      _successMessage = null;
      _hasLoaded = false;
      notifyListeners();
      return;
    }

    if (roleChanged || !_hasLoaded) {
      await refresh();
    }
  }

  Future<void> refresh() async {
    final repository = _repository;
    if (!_isAdministrator || repository == null || _isLoading) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final failedSections = <String>[];

    try {
      try {
        _settings = await repository.fetchSettings();
      } catch (_) {
        failedSections.add('automation settings');
      }

      try {
        _health = await repository.fetchContentHealth();
      } catch (_) {
        failedSections.add('content health');
      }

      try {
        _drafts = await repository.fetchDrafts();
      } catch (_) {
        failedSections.add('generated drafts');
      }

      try {
        _questionReviewQueue = await repository.fetchQuestionReviewQueue();
      } catch (_) {
        failedSections.add('question review queue');
      }

      try {
        _approvedQuestions = await repository.fetchApprovedQuestions();
      } catch (_) {
        failedSections.add('approved question bank');
      }

      try {
        _sources = await repository.fetchSources();
      } catch (_) {
        failedSections.add('trusted sources');
      }

      try {
        _queueHealth = await repository.fetchQueueHealth();
      } catch (_) {
        _queueHealth = QueueLifecycleStats.empty();
        failedSections.add('queue lifecycle');
      }

      _hasLoaded = true;
      if (failedSections.isNotEmpty) {
        _errorMessage =
            'Learning Studio opened, but some online sections could not load: ${failedSections.join(', ')}. Check the Phase 7 Supabase policies/data, then retry.';
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> setSourceEnabled(String sourceId, bool enabled) async {
    return _mutate(() async {
      await _requireRepository().setSourceEnabled(sourceId, enabled);
      await refresh();
    });
  }

  Future<bool> saveSettings({
    required bool enabled,
    required int maxArticlesPerRun,
    required int maxDraftsPerDay,
    required int monthlyDraftCap,
    required int maxPendingDrafts,
    required int maxPendingQuestions,
    required int draftArchiveDays,
  }) async {
    return _mutate(() async {
      await _requireRepository().updateSettings(
        enabled: enabled,
        maxArticlesPerRun: maxArticlesPerRun,
        maxDraftsPerDay: maxDraftsPerDay,
        monthlyDraftCap: monthlyDraftCap,
        maxPendingDrafts: maxPendingDrafts,
        maxPendingQuestions: maxPendingQuestions,
        draftArchiveDays: draftArchiveDays,
      );
      await refresh();
    });
  }

  Future<bool> runNow() async {
    return _mutate(() async {
      final message = await _requireRepository().runAutomationNow();
      _successMessage = message;
      await refresh();
    });
  }

  Future<bool> publishDraft(String draftId) async {
    return _mutate(() async {
      await _requireRepository().publishDraft(draftId);
      _successMessage =
          'Draft approved to Content Management. It is still a draft and is not learner-visible yet.';
      await refresh();
    });
  }

  Future<bool> rejectDraft(String draftId) async {
    return _mutate(() async {
      await _requireRepository().rejectDraft(draftId);
      _successMessage = 'Draft rejected.';
      await refresh();
    });
  }

  Future<bool> verifyQuestion(QuestionBankReviewItem question) async {
    return _mutate(() async {
      await _requireRepository().verifyQuestion(question);
      _successMessage =
          'Question verified. It will become learner-visible when its linked lesson is published.';
      await refresh();
    });
  }

  Future<bool> rejectQuestion(String questionId) async {
    return _mutate(() async {
      await _requireRepository().rejectQuestion(questionId);
      _successMessage = 'Question rejected and archived.';
      await refresh();
    });
  }

  void clearMessages() {
    if (_errorMessage == null && _successMessage == null) return;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
  }

  Future<bool> _mutate(Future<void> Function() operation) async {
    if (_isMutating || !_isAdministrator || _repository == null) return false;
    _isMutating = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
    try {
      await operation();
      return true;
    } catch (error) {
      _errorMessage = _friendlyMessage(error);
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  ContentAutomationRepository _requireRepository() {
    final repository = _repository;
    if (repository == null) {
      throw StateError('Content automation is not configured.');
    }
    return repository;
  }

  String _friendlyMessage(Object error) {
    final value = error.toString().toLowerCase();
    if (value.contains('cooldown')) {
      return 'Manual content checks are temporarily on cooldown.';
    }
    if (value.contains('groq_api_key')) {
      return 'Content automation needs the GROQ_API_KEY Supabase secret before it can generate drafts.';
    }
    if (value.contains('administrator access') || value.contains('403')) {
      return 'Administrator access is required for this Learning Studio action.';
    }
    if (value.contains('content-automation') ||
        value.contains('function') ||
        value.contains('failed to fetch')) {
      return 'The content-automation Edge Function is not deployed or could not be reached.';
    }
    return 'The Learning Studio action could not be completed.';
  }
}
