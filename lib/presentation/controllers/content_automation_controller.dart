import 'package:flutter/foundation.dart';

import '../../data/models/content_automation.dart';
import '../../data/repositories/content_automation_repository.dart';

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
      // Keep admin-only data lazy. The Learning Studio screen requests it when
      // opened instead of adding seven Supabase reads to normal sign-in.
      _hasLoaded = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    final repository = _repository;
    if (!_isAdministrator || repository == null || _isLoading) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final failedSections = <String>[];

    // These sections are independent. Start all reads together to reduce the
    // total network wait from seven sequential round trips to roughly one.
    final settingsFuture = repository.fetchSettings();
    final healthFuture = repository.fetchContentHealth();
    final draftsFuture = repository.fetchDrafts();
    final reviewFuture = repository.fetchQuestionReviewQueue();
    final approvedFuture = repository.fetchApprovedQuestions();
    final sourcesFuture = repository.fetchSources();
    final queueFuture = repository.fetchQueueHealth();

    try {
      try {
        _settings = await settingsFuture;
      } catch (_) {
        failedSections.add('automation settings');
      }

      try {
        _health = await healthFuture;
      } catch (_) {
        failedSections.add('content health');
      }

      try {
        _drafts = await draftsFuture;
      } catch (_) {
        failedSections.add('generated drafts');
      }

      try {
        _questionReviewQueue = await reviewFuture;
      } catch (_) {
        failedSections.add('question review queue');
      }

      try {
        _approvedQuestions = await approvedFuture;
      } catch (_) {
        failedSections.add('approved question bank');
      }

      try {
        _sources = await sourcesFuture;
      } catch (_) {
        failedSections.add('trusted sources');
      }

      try {
        _queueHealth = await queueFuture;
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
      _sources = _sources
          .map(
            (source) => source.id == sourceId
                ? ContentSource(
                    id: source.id,
                    name: source.name,
                    sourceUrl: source.sourceUrl,
                    feedUrl: source.feedUrl,
                    sourceType: source.sourceType,
                    trustLevel: source.trustLevel,
                    enabled: enabled,
                    lastCheckedAt: source.lastCheckedAt,
                  )
                : source,
          )
          .toList(growable: false);
      _successMessage = enabled ? 'Source enabled.' : 'Source disabled.';
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
      _settings = AutomationSettings(
        enabled: enabled,
        maxArticlesPerRun: maxArticlesPerRun,
        maxDraftsPerDay: maxDraftsPerDay,
        monthlyDraftCap: monthlyDraftCap,
        manualCooldownMinutes: _settings.manualCooldownMinutes,
        maxPendingDrafts: maxPendingDrafts,
        maxPendingQuestions: maxPendingQuestions,
        draftArchiveDays: draftArchiveDays,
        rejectedDeleteDays: _settings.rejectedDeleteDays,
        archivedDeleteDays: _settings.archivedDeleteDays,
        lastManualRunAt: _settings.lastManualRunAt,
      );
      _queueHealth = QueueLifecycleStats(
        pendingDrafts: _queueHealth.pendingDrafts,
        pendingQuestions: _queueHealth.pendingQuestions,
        archivedDrafts: _queueHealth.archivedDrafts,
        expiringDraftsSoon: _queueHealth.expiringDraftsSoon,
        expiringQuestionsSoon: _queueHealth.expiringQuestionsSoon,
        maxPendingDrafts: maxPendingDrafts,
        maxPendingQuestions: maxPendingQuestions,
        draftArchiveDays: draftArchiveDays,
        rejectedDeleteDays: _queueHealth.rejectedDeleteDays,
        archivedDeleteDays: _queueHealth.archivedDeleteDays,
      );
      _successMessage = 'Learning Studio automation settings updated.';
    });
  }

  Future<bool> runNow() async {
    return _mutate(() async {
      final message = await _requireRepository().runAutomationNow();
      _successMessage = message;
      await refresh();
    });
  }

  Future<bool> runVerificationDraftsNow() async {
    return _mutate(() async {
      final message = await _requireRepository().runVerificationDraftsNow();
      _successMessage = message;
      // Verification Studio owns the Verify draft/case data and refreshes only
      // those sections after generation. Do not reload all seven Learning
      // Studio datasets for an unrelated Verify-only operation.
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
    final raw = error.toString().replaceFirst('Bad state: ', '').trim();
    final value = raw.toLowerCase();

    if (value.contains('cooldown') ||
        value.contains('try again in about') ||
        value.contains('already started moments ago')) {
      return raw;
    }
    if (value.contains('groq_api_key')) {
      return 'Content automation needs the GROQ_API_KEY Supabase secret before it can generate drafts.';
    }
    if (value.contains('no current awareness articles') ||
        value.contains('source fetch failed') ||
        value.contains('insufficient text') ||
        value.contains('ai generation failed') ||
        value.contains('draft save failed') ||
        value.contains('no eligible source')) {
      return raw;
    }
    if (value.contains('administrator access') || value.contains('403')) {
      return 'Administrator access is required for this Learning Studio action.';
    }
    if (value.contains('content-automation') ||
        value.contains('function') ||
        value.contains('failed to fetch')) {
      return 'The content-automation Edge Function is not deployed or could not be reached.';
    }
    if (raw.isNotEmpty && raw.length <= 360) return raw;
    return 'The Learning Studio action could not be completed.';
  }
}
