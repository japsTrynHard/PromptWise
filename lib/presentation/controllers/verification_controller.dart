import 'package:flutter/foundation.dart';

import '../../data/models/verification.dart';
import '../../data/repositories/verification_repository.dart';

class VerificationController extends ChangeNotifier {
  final VerificationRepository? _repository;

  VerificationController({VerificationRepository? repository})
      : _repository = repository;

  String? _activeUserId;
  int _requestEpoch = 0;
  bool _isLoading = false;
  bool _isStarting = false;
  bool _isSubmitting = false;
  bool _isCompleting = false;
  bool _hasLoaded = false;
  DateTime? _lastLoadedAt;
  Future<void>? _refreshFuture;
  String? _errorMessage;
  VerificationSession? _session;
  VerificationSessionSummary? _summary;
  int _caseIndex = 0;
  final Map<String, VerificationCaseFeedback> _feedback = {};
  Map<VerificationSubskill, VerificationSubskillMastery> _mastery = {
    for (final subskill in VerificationSubskill.values)
      subskill: VerificationSubskillMastery.initial(subskill),
  };

  bool get isLoading => _isLoading;
  bool get isStarting => _isStarting;
  bool get isSubmitting => _isSubmitting;
  bool get isCompleting => _isCompleting;
  bool get hasLoaded => _hasLoaded;
  DateTime? get lastLoadedAt => _lastLoadedAt;
  String? get errorMessage => _errorMessage;
  VerificationSession? get session => _session;
  VerificationSessionSummary? get summary => _summary;
  int get caseIndex => _caseIndex;
  Map<String, VerificationCaseFeedback> get feedback =>
      Map.unmodifiable(_feedback);
  Map<VerificationSubskill, VerificationSubskillMastery> get mastery =>
      Map.unmodifiable(_mastery);

  VerificationCase? get currentCase {
    final session = _session;
    if (session == null || session.cases.isEmpty) return null;
    if (_caseIndex < 0 || _caseIndex >= session.cases.length) return null;
    return session.cases[_caseIndex];
  }

  bool get hasActiveSession => _session != null && _summary == null;
  bool get isComplete => _summary != null;

  VerificationSubskillMastery masteryFor(VerificationSubskill subskill) =>
      _mastery[subskill] ?? VerificationSubskillMastery.initial(subskill);

  VerificationSubskill get weakestSubskill {
    var weakest = VerificationSubskill.values.first;
    var lowest = 101;
    for (final subskill in VerificationSubskill.values) {
      final value = masteryFor(subskill).mastery;
      if (value < lowest) {
        lowest = value;
        weakest = subskill;
      }
    }
    return weakest;
  }

  Future<void> bindAuthenticatedUser(String? userId) async {
    if (_activeUserId == userId) return;

    _activeUserId = userId;
    _requestEpoch += 1;

    // Any request started for the previous account is now stale. Reset local
    // busy flags so a fast sign-out/sign-in cannot leave Verify permanently
    // stuck in a loading state while an older network request finishes.
    _isLoading = false;
    _isStarting = false;
    _isSubmitting = false;
    _isCompleting = false;
    _hasLoaded = false;
    _lastLoadedAt = null;
    _refreshFuture = null;
    _clearSession(notify: false);
    // Mastery is account-specific. Clear it immediately on every account
    // switch so a lazy first load cannot show the previous learner's values.
    _mastery = _initialMastery();
    _errorMessage = null;
    // Verify progress is lazy: no Supabase read is made until the learner
    // actually opens Verify or explicitly refreshes it.
    notifyListeners();
  }

  Future<void> ensureLoaded({
    Duration maxAge = const Duration(minutes: 5),
  }) async {
    final last = _lastLoadedAt;
    if (_hasLoaded && last != null && DateTime.now().difference(last) < maxAge) {
      return;
    }
    await refresh(force: false);
  }

  Future<void> refresh({bool force = true}) {
    final existing = _refreshFuture;
    if (existing != null) return existing;

    final userId = _activeUserId;
    final repository = _repository;
    final epoch = _requestEpoch;
    if (userId == null || repository == null) return Future<void>.value();
    if (!force &&
        _hasLoaded &&
        _lastLoadedAt != null &&
        DateTime.now().difference(_lastLoadedAt!) < const Duration(minutes: 5)) {
      return Future<void>.value();
    }

    late final Future<void> future;
    future = _refreshInternal(userId, repository, epoch).whenComplete(() {
      if (identical(_refreshFuture, future)) _refreshFuture = null;
    });
    _refreshFuture = future;
    return future;
  }

  Future<void> _refreshInternal(
    String userId,
    VerificationRepository repository,
    int epoch,
  ) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final fetched = await repository.fetchSubskillMastery();
      if (!_isCurrentRequest(userId, epoch)) return;

      _mastery = {
        for (final subskill in VerificationSubskill.values)
          subskill: VerificationSubskillMastery.initial(subskill),
        for (final item in fetched) item.subskill: item,
      };
      _hasLoaded = true;
      _lastLoadedAt = DateTime.now();
    } catch (_) {
      if (_isCurrentRequest(userId, epoch)) {
        _errorMessage =
            'Verification progress could not be refreshed. Check your connection and try again.';
      }
    } finally {
      if (_isCurrentRequest(userId, epoch)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> startSession({
    int caseCount = 5,
    required int rankLevel,
  }) async {
    final repository = _repository;
    final userId = _activeUserId;
    final epoch = _requestEpoch;
    if (userId == null || repository == null || _isStarting) return false;

    _isStarting = true;
    _errorMessage = null;
    _clearSession(notify: false);
    notifyListeners();

    try {
      final session = await repository.createSession(
        caseCount: caseCount,
        rankLevel: rankLevel,
      );
      if (!_isCurrentRequest(userId, epoch)) return false;

      _session = session;
      _caseIndex = 0;
      return true;
    } catch (error) {
      if (_isCurrentRequest(userId, epoch)) {
        _errorMessage = _friendlyMessage(error);
      }
      return false;
    } finally {
      if (_isCurrentRequest(userId, epoch)) {
        _isStarting = false;
        notifyListeners();
      }
    }
  }

  Future<VerificationCaseFeedback?> submitCurrentGuess({
    required VerificationDecision decision,
  }) async {
    final repository = _repository;
    final userId = _activeUserId;
    final epoch = _requestEpoch;
    final session = _session;
    final current = currentCase;

    if (userId == null ||
        repository == null ||
        session == null ||
        current == null ||
        _isSubmitting ||
        _feedback.containsKey(current.id)) {
      return null;
    }

    final sessionId = session.id;
    final caseId = current.id;
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await repository.submitGuess(
        sessionId: sessionId,
        caseId: caseId,
        decision: decision,
      );

      if (!_isCurrentRequest(userId, epoch) ||
          _session?.id != sessionId ||
          currentCase?.id != caseId) {
        return null;
      }

      _feedback[caseId] = result;
      if (result.subskillMasteryAfter != null) {
        final previous = masteryFor(result.subskill);
        _mastery[result.subskill] = VerificationSubskillMastery(
          subskill: result.subskill,
          mastery: result.subskillMasteryAfter!,
          attempts: previous.attempts + (result.countedForMastery ? 1 : 0),
          successfulAttempts: previous.successfulAttempts +
              (result.countedForMastery && result.decisionCorrect ? 1 : 0),
          lastPracticedAt: DateTime.now(),
          nextReviewAt: previous.nextReviewAt,
        );
      }
      return result;
    } catch (error) {
      if (_isCurrentRequest(userId, epoch)) {
        _errorMessage = _friendlyMessage(error);
      }
      return null;
    } finally {
      if (_isCurrentRequest(userId, epoch)) {
        _isSubmitting = false;
        notifyListeners();
      }
    }
  }

  Future<bool> nextCaseOrComplete() async {
    final session = _session;
    final current = currentCase;
    if (session == null ||
        current == null ||
        !_feedback.containsKey(current.id)) {
      return false;
    }

    if (_caseIndex < session.cases.length - 1) {
      _caseIndex += 1;
      notifyListeners();
      return true;
    }

    return completeSession();
  }

  Future<bool> completeSession() async {
    final repository = _repository;
    final userId = _activeUserId;
    final epoch = _requestEpoch;
    final session = _session;

    if (userId == null ||
        repository == null ||
        session == null ||
        _isCompleting) {
      return false;
    }
    if (_feedback.length < session.cases.length) return false;

    final sessionId = session.id;
    _isCompleting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final summary = await repository.completeSession(sessionId);
      if (!_isCurrentRequest(userId, epoch) || _session?.id != sessionId) {
        return false;
      }

      _summary = summary;
      _hasLoaded = true;
      _lastLoadedAt = DateTime.now();
      return _isCurrentRequest(userId, epoch) && _summary != null;
    } catch (error) {
      if (_isCurrentRequest(userId, epoch)) {
        _errorMessage = _friendlyMessage(error);
      }
      return false;
    } finally {
      if (_isCurrentRequest(userId, epoch)) {
        _isCompleting = false;
        notifyListeners();
      }
    }
  }

  Future<void> abandonSession() async {
    final session = _session;
    final repository = _repository;
    final shouldNotifyServer = _summary == null;

    // Clear the local session immediately so leaving the screen is reliable even
    // on a weak connection. The server call below is best-effort cleanup only.
    _clearSession(notify: true);

    if (shouldNotifyServer && session != null && repository != null) {
      try {
        await repository.abandonSession(session.id);
      } catch (_) {
        // The learner must still be able to leave if the network drops.
      }
    }
  }

  void clearSession() => _clearSession(notify: true);

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  Map<VerificationSubskill, VerificationSubskillMastery> _initialMastery() => {
        for (final subskill in VerificationSubskill.values)
          subskill: VerificationSubskillMastery.initial(subskill),
      };

  bool _isCurrentRequest(String userId, int epoch) =>
      _activeUserId == userId && _requestEpoch == epoch;

  void _clearSession({required bool notify}) {
    _session = null;
    _summary = null;
    _caseIndex = 0;
    _feedback.clear();
    if (notify) notifyListeners();
  }

  String _friendlyMessage(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('no eligible') || text.contains('no verification case')) {
      return 'There are not enough Verify examples for this level yet. Please try again after more content is added.';
    }
    if (text.contains('network') ||
        text.contains('socket') ||
        text.contains('connection') ||
        text.contains('timeout')) {
      return 'Quick Check needs an internet connection so your answers can be saved.';
    }
    if (text.contains('jwt') || text.contains('unauthorized') || text.contains('401')) {
      return 'Your session expired. Sign in again, then reopen Verify.';
    }
    return 'Quick Check could not continue. Please try again.';
  }
}

class VerificationStudioController extends ChangeNotifier {
  final VerificationRepository? _repository;

  VerificationStudioController({VerificationRepository? repository})
      : _repository = repository;

  bool _isAdministrator = false;
  int _adminEpoch = 0;
  bool _isLoading = false;
  bool _isMutating = false;
  bool _hasLoaded = false;
  String? _errorMessage;
  String? _successMessage;
  List<VerificationCaseDraft> _drafts = const [];
  List<VerificationCaseHealth> _health = const [];
  List<VerificationCase> _cases = const [];
  VerificationAutomationOverview _automationOverview =
      VerificationAutomationOverview.defaults();

  bool get isAdministrator => _isAdministrator;
  bool get isLoading => _isLoading;
  bool get isMutating => _isMutating;
  bool get hasLoaded => _hasLoaded;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;
  List<VerificationCaseDraft> get drafts => List.unmodifiable(_drafts);
  List<VerificationCaseHealth> get health => List.unmodifiable(_health);
  List<VerificationCase> get cases => List.unmodifiable(_cases);
  VerificationAutomationOverview get automationOverview => _automationOverview;

  Future<void> bindAdministrator(bool isAdministrator) async {
    final changed = _isAdministrator != isAdministrator;
    if (changed) _adminEpoch += 1;
    _isAdministrator = isAdministrator;

    if (!isAdministrator) {
      _isLoading = false;
      _isMutating = false;
      _drafts = const [];
      _health = const [];
      _cases = const [];
      _automationOverview = VerificationAutomationOverview.defaults();
      _hasLoaded = false;
      _errorMessage = null;
      _successMessage = null;
      notifyListeners();
      return;
    }

    if (changed || !_hasLoaded) {
      // Loading is intentionally lazy. The Studio screen requests data only
      // when an administrator actually opens it, which removes four Supabase
      // round trips from normal sign-in/navigation.
      _hasLoaded = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    final repository = _repository;
    final epoch = _adminEpoch;
    if (!_isAdministrator || repository == null || _isLoading) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final failures = <String>[];
    var nextDrafts = _drafts;
    var nextHealth = _health;
    var nextCases = _cases;
    var nextOverview = _automationOverview;

    // Start independent reads together instead of waiting for each network
    // request one-by-one. This substantially lowers Studio load latency.
    final draftsFuture = repository.fetchDrafts();
    final healthFuture = repository.fetchHealth();
    final casesFuture = repository.fetchPublishedCases();
    final overviewFuture = repository.fetchAutomationOverview();

    try {
      try {
        nextDrafts = await draftsFuture;
      } catch (_) {
        failures.add('AI case drafts');
      }
      if (!_isCurrentAdmin(epoch)) return;

      try {
        nextHealth = await healthFuture;
      } catch (_) {
        failures.add('case health');
      }
      if (!_isCurrentAdmin(epoch)) return;

      try {
        nextCases = await casesFuture;
      } catch (_) {
        failures.add('case bank');
      }
      if (!_isCurrentAdmin(epoch)) return;

      try {
        nextOverview = await overviewFuture;
      } catch (_) {
        failures.add('Verify automation limits');
      }
      if (!_isCurrentAdmin(epoch)) return;

      _drafts = nextDrafts;
      _health = nextHealth;
      _cases = nextCases;
      _automationOverview = nextOverview;
      _hasLoaded = true;
      if (failures.isNotEmpty) {
        _errorMessage =
            'Verification Studio opened, but some sections could not load: ${failures.join(', ')}.';
      }
    } finally {
      if (_isCurrentAdmin(epoch)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> saveAutomationSettings({
    required bool enabled,
    required int maxArticlesPerRun,
    required int maxDraftsPerRun,
    required int maxDraftsPerDay,
    required int monthlyDraftCap,
    required int monthlyGroqRequestCap,
    required int maxPendingDrafts,
    required int manualCooldownMinutes,
  }) =>
      _mutate(
        successMessage: 'Verify automation limits updated.',
        refreshAfter: false,
        action: () async {
          await _requireRepository().updateAutomationSettings(
            enabled: enabled,
            maxArticlesPerRun: maxArticlesPerRun,
            maxDraftsPerRun: maxDraftsPerRun,
            maxDraftsPerDay: maxDraftsPerDay,
            monthlyDraftCap: monthlyDraftCap,
            monthlyGroqRequestCap: monthlyGroqRequestCap,
            maxPendingDrafts: maxPendingDrafts,
            manualCooldownMinutes: manualCooldownMinutes,
          );
          final current = _automationOverview;
          _automationOverview = VerificationAutomationOverview(
            enabled: enabled,
            maxArticlesPerRun: maxArticlesPerRun,
            maxDraftsPerRun: maxDraftsPerRun,
            maxDraftsPerDay: maxDraftsPerDay,
            monthlyDraftCap: monthlyDraftCap,
            monthlyGroqRequestCap: monthlyGroqRequestCap,
            maxPendingDrafts: maxPendingDrafts,
            manualCooldownMinutes: manualCooldownMinutes,
            pendingDrafts: current.pendingDrafts,
            draftsToday: current.draftsToday,
            draftsThisMonth: current.draftsThisMonth,
            groqRequestsThisMonth: current.groqRequestsThisMonth,
            groqRequestsRemaining:
                (monthlyGroqRequestCap - current.groqRequestsThisMonth)
                    .clamp(0, monthlyGroqRequestCap)
                    .toInt(),
            cooldownRemainingMinutes: current.cooldownRemainingMinutes,
            remainingToday: (maxDraftsPerDay - current.draftsToday)
                .clamp(0, maxDraftsPerDay)
                .toInt(),
            remainingThisMonth: (monthlyDraftCap - current.draftsThisMonth)
                .clamp(0, monthlyDraftCap)
                .toInt(),
          );
        },
      );


  Future<bool> approveDraft(String draftId) => _mutate(
        successMessage: 'Verification case approved to the published case bank.',
        action: () => _requireRepository().approveDraft(draftId),
      );

  Future<bool> rejectDraft(String draftId) => _mutate(
        successMessage: 'Verification case draft rejected.',
        action: () => _requireRepository().rejectDraft(draftId),
      );

  Future<bool> updateCase({
    required VerificationCase item,
    required String title,
    required String scenario,
    required String claimText,
    required VerificationSubskill subskill,
    required VerificationCaseType caseType,
    required int difficulty,
    required VerificationDecision correctDecision,
    required VerificationConfidence expectedConfidence,
    required String explanation,
    required String learningPoint,
  }) =>
      _mutate(
        successMessage: 'Verification case updated.',
        action: () => _requireRepository().updateCase(
          caseId: item.id,
          title: title,
          scenario: scenario,
          claimText: claimText,
          subskill: subskill,
          caseType: caseType,
          difficulty: difficulty,
          correctDecision: correctDecision,
          expectedConfidence: expectedConfidence,
          explanation: explanation,
          learningPoint: learningPoint,
        ),
      );

  Future<bool> archiveCase(String caseId) => _mutate(
        successMessage: 'Verification case archived.',
        action: () => _requireRepository().archiveCase(caseId),
      );

  void clearMessages() {
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
  }

  Future<bool> _mutate({
    required String successMessage,
    required Future<void> Function() action,
    bool refreshAfter = true,
  }) async {
    final epoch = _adminEpoch;
    if (_isMutating || !_isAdministrator || _repository == null) return false;

    _isMutating = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    try {
      await action();
      if (!_isCurrentAdmin(epoch)) return false;

      _successMessage = successMessage;
      if (refreshAfter) {
        await refresh();
      }
      return _isCurrentAdmin(epoch);
    } catch (_) {
      if (_isCurrentAdmin(epoch)) {
        _errorMessage = 'The Verification Studio action could not be completed.';
      }
      return false;
    } finally {
      if (_isCurrentAdmin(epoch)) {
        _isMutating = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrentAdmin(int epoch) =>
      _isAdministrator && _adminEpoch == epoch;

  VerificationRepository _requireRepository() {
    final repository = _repository;
    if (repository == null) {
      throw StateError('Verification backend is unavailable.');
    }
    return repository;
  }
}
