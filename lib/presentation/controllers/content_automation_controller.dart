import 'package:flutter/foundation.dart';

import '../../data/models/content_automation.dart';
import '../../data/repositories/content_automation_repository.dart';

class ContentAutomationController extends ChangeNotifier {
  final ContentAutomationRepository? _repository;

  ContentAutomationController({ContentAutomationRepository? repository})
    : _repository = repository;

  bool _isAdministrator = false;
  String? _administratorUserId;
  int _adminEpoch = 0;
  bool _disposed = false;
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

  Future<void> bindAdministrator(bool isAdministrator, {String? userId}) async {
    if (_disposed) return;
    final roleChanged =
        _isAdministrator != isAdministrator || _administratorUserId != userId;
    _isAdministrator = isAdministrator;
    _administratorUserId = isAdministrator ? userId : null;
    if (roleChanged) _adminEpoch++;

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
      _isLoading = false;
      _isMutating = false;
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
    final epoch = _adminEpoch;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final failedSections = <String>[];

    // These sections are independent. Start all reads together to reduce the
    // total network wait from seven sequential round trips to roughly one.
    final settingsFuture = _capture(repository.fetchSettings());
    final healthFuture = _capture(repository.fetchContentHealth());
    final draftsFuture = _capture(repository.fetchDrafts());
    final reviewFuture = _capture(repository.fetchQuestionReviewQueue());
    final approvedFuture = _capture(repository.fetchApprovedQuestions());
    final sourcesFuture = _capture(repository.fetchSources());
    final queueFuture = _capture(repository.fetchQueueHealth());

    try {
      final settingsResult = await settingsFuture;
      if (!_isCurrentAdmin(epoch)) return;
      if (settingsResult.value != null) {
        _settings = settingsResult.value!;
      } else {
        failedSections.add('automation settings');
      }

      final healthResult = await healthFuture;
      if (!_isCurrentAdmin(epoch)) return;
      if (healthResult.value != null) {
        _health = healthResult.value!;
      } else {
        failedSections.add('content health');
      }

      final draftsResult = await draftsFuture;
      if (!_isCurrentAdmin(epoch)) return;
      if (draftsResult.value != null) {
        _drafts = draftsResult.value!;
      } else {
        failedSections.add('generated drafts');
      }

      final reviewResult = await reviewFuture;
      if (!_isCurrentAdmin(epoch)) return;
      if (reviewResult.value != null) {
        _questionReviewQueue = reviewResult.value!;
      } else {
        failedSections.add('question review queue');
      }

      final approvedResult = await approvedFuture;
      if (!_isCurrentAdmin(epoch)) return;
      if (approvedResult.value != null) {
        _approvedQuestions = approvedResult.value!;
      } else {
        failedSections.add('approved question bank');
      }

      final sourcesResult = await sourcesFuture;
      if (!_isCurrentAdmin(epoch)) return;
      if (sourcesResult.value != null) {
        _sources = sourcesResult.value!;
      } else {
        failedSections.add('trusted sources');
      }

      final queueResult = await queueFuture;
      if (!_isCurrentAdmin(epoch)) return;
      if (queueResult.value != null) {
        _queueHealth = queueResult.value!;
      } else {
        _queueHealth = QueueLifecycleStats.empty();
        failedSections.add('queue lifecycle');
      }

      _hasLoaded = true;
      if (failedSections.isNotEmpty) {
        _errorMessage =
            'Learning Studio opened, but some online sections could not load: ${failedSections.join(', ')}. Check the Phase 7 Supabase policies/data, then retry.';
      }
    } finally {
      if (_isCurrentAdmin(epoch)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> setSourceEnabled(String sourceId, bool enabled) async {
    return _mutate((isCurrent) async {
      await _requireRepository().setSourceEnabled(sourceId, enabled);
      if (!isCurrent()) return;
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
    return _mutate((isCurrent) async {
      await _requireRepository().updateSettings(
        enabled: enabled,
        maxArticlesPerRun: maxArticlesPerRun,
        maxDraftsPerDay: maxDraftsPerDay,
        monthlyDraftCap: monthlyDraftCap,
        maxPendingDrafts: maxPendingDrafts,
        maxPendingQuestions: maxPendingQuestions,
        draftArchiveDays: draftArchiveDays,
      );
      if (!isCurrent()) return;
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
    return _mutate((isCurrent) async {
      final message = await _requireRepository().runAutomationNow();
      if (!isCurrent()) return;
      _successMessage = message;
      await refresh();
    });
  }

  Future<bool> runVerificationDraftsNow() async {
    return _mutate((isCurrent) async {
      final message = await _requireRepository().runVerificationDraftsNow();
      if (!isCurrent()) return;
      _successMessage = message;
      // Verification Studio owns the Verify draft/case data and refreshes only
      // those sections after generation. Do not reload all seven Learning
      // Studio datasets for an unrelated Verify-only operation.
    });
  }

  Future<bool> publishDraft(String draftId) async {
    return _mutate((isCurrent) async {
      await _requireRepository().publishDraft(draftId);
      if (!isCurrent()) return;
      _successMessage =
          'Draft approved to Content Management. It is still a draft and is not learner-visible yet.';
      await refresh();
    });
  }

  Future<bool> rejectDraft(String draftId) async {
    return _mutate((isCurrent) async {
      await _requireRepository().rejectDraft(draftId);
      if (!isCurrent()) return;
      _successMessage = 'Draft rejected.';
      await refresh();
    });
  }

  Future<bool> verifyQuestion(QuestionBankReviewItem question) async {
    return _mutate((isCurrent) async {
      await _requireRepository().verifyQuestion(question);
      if (!isCurrent()) return;
      _successMessage =
          'Question verified. It will become learner-visible when its linked lesson is published.';
      await refresh();
    });
  }

  Future<bool> rejectQuestion(String questionId) async {
    return _mutate((isCurrent) async {
      await _requireRepository().rejectQuestion(questionId);
      if (!isCurrent()) return;
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

  Future<bool> _mutate(
    Future<void> Function(bool Function() isCurrent) operation,
  ) async {
    if (_isMutating || !_isAdministrator || _repository == null) return false;
    final epoch = _adminEpoch;
    _isMutating = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
    try {
      await operation(() => _isCurrentAdmin(epoch));
      if (!_isCurrentAdmin(epoch)) return false;
      return true;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Learning Studio mutation failed: $error\n$stackTrace');
      }
      if (_isCurrentAdmin(epoch)) {
        _errorMessage = _friendlyMessage(error);
      }
      return false;
    } finally {
      if (_isCurrentAdmin(epoch)) {
        _isMutating = false;
        notifyListeners();
      }
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

  bool _isCurrentAdmin(int epoch) =>
      !_disposed &&
      _isAdministrator &&
      _administratorUserId != null &&
      _adminEpoch == epoch;

  Future<_AdminLoadResult<T>> _capture<T>(Future<T> request) async {
    try {
      return _AdminLoadResult<T>.success(await request);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Learning Studio section failed: $error\n$stackTrace');
      }
      return _AdminLoadResult<T>.failure(error);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _adminEpoch++;
    super.dispose();
  }
}

class _AdminLoadResult<T> {
  final T? value;
  final Object? error;

  const _AdminLoadResult._(this.value, this.error);

  factory _AdminLoadResult.success(T value) =>
      _AdminLoadResult<T>._(value, null);

  factory _AdminLoadResult.failure(Object error) =>
      _AdminLoadResult<T>._(null, error);
}
