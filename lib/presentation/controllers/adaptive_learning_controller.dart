import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/models/adaptive_learning.dart';
import '../../data/models/learning_topic.dart';
import '../../data/models/quiz.dart';
import '../../data/repositories/adaptive_learning_repository.dart';
import '../../data/services/storage_service.dart';

class AdaptiveLearningController extends ChangeNotifier {
  final AdaptiveLearningRepository? _repository;
  final StorageService _storage;

  AdaptiveLearningController({
    AdaptiveLearningRepository? repository,
    StorageService? storage,
  }) : _repository = repository,
       _storage = storage ?? StorageService();

  Map<LearningTopic, TopicMastery> _mastery = _initialMastery();
  final Set<String> _countedAttemptKeys = <String>{};
  final Map<String, DateTime> _lastCountedAttemptByItemTopic =
      <String, DateTime>{};
  String? _activeUserId;
  bool _diagnosticCompleted = false;
  bool _isLoading = false;
  bool _isSubmittingDiagnostic = false;
  bool _isSynchronizingExistingProgress = false;
  String? _errorMessage;
  DateTime? _lastSyncedAt;
  Future<void>? _bindingFuture;
  String? _bindingUserId;
  Future<void>? _existingProgressSyncFuture;
  List<Quiz>? _pendingExistingProgressQuizzes;
  Map<String, int>? _pendingExistingProgressScores;
  String? _lastExistingProgressSignature;
  String? _pendingExistingProgressSignature;

  Map<LearningTopic, TopicMastery> get mastery => Map.unmodifiable(_mastery);
  bool get diagnosticCompleted => _diagnosticCompleted;
  bool get isLoading => _isLoading;
  bool get isSubmittingDiagnostic => _isSubmittingDiagnostic;
  bool get isSynchronizingExistingProgress => _isSynchronizingExistingProgress;
  String? get errorMessage => _errorMessage;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  bool get isCloudSyncEnabled => _activeUserId != null && _repository != null;

  int get overallMastery {
    final attempted = _mastery.values
        .where((item) => item.attempts > 0)
        .toList(growable: false);
    if (attempted.isEmpty) return 0;
    final total = attempted.fold<int>(0, (sum, item) => sum + item.mastery);
    return (total / attempted.length).round().clamp(0, 100).toInt();
  }

  List<TopicMastery> get rankedTopics {
    final values = _mastery.values.toList(growable: false)
      ..sort((a, b) {
        if (a.attempts == 0 && b.attempts != 0) return 1;
        if (b.attempts == 0 && a.attempts != 0) return -1;
        final byMastery = a.mastery.compareTo(b.mastery);
        return byMastery != 0
            ? byMastery
            : a.topic.label.compareTo(b.topic.label);
      });
    return values;
  }

  List<TopicMastery> get dueReviews {
    final due = _mastery.values
        .where((item) => item.attempts > 0 && item.isDueForReview)
        .toList();
    due.sort((a, b) {
      final aDue = a.nextReviewAt ?? DateTime.now();
      final bDue = b.nextReviewAt ?? DateTime.now();
      return aDue.compareTo(bDue);
    });
    return due;
  }

  LearningTopic? get weakestTopic {
    final attempted = rankedTopics.where((item) => item.attempts > 0);
    return attempted.isEmpty ? null : attempted.first.topic;
  }

  LearningTopic? get recommendedTopic {
    if (!_diagnosticCompleted &&
        _mastery.values.every((item) => item.attempts == 0)) {
      return null;
    }
    if (dueReviews.isNotEmpty) return dueReviews.first.topic;
    return weakestTopic;
  }

  String get recommendationReason {
    if (!_diagnosticCompleted) {
      return 'Complete the diagnostic assessment so PromptWise can personalize your next steps.';
    }
    if (dueReviews.isNotEmpty) {
      return '${dueReviews.first.topic.label} is due for a short review.';
    }
    final weakest = weakestTopic;
    if (weakest == null) {
      return 'Complete a lesson or knowledge check to begin building your mastery profile.';
    }
    return '${weakest.label} is currently your lowest mastery area.';
  }

  TopicMastery masteryFor(LearningTopic topic) =>
      _mastery[topic] ?? TopicMastery.initial(topic);

  /// Whether this exact item is currently eligible to add mastery evidence.
  /// Recommendations use this so they never present an immediate retry as if
  /// it could change mastery when its review window is still closed.
  bool canCountEvidenceNow({
    required String itemId,
    required LearningTopic topic,
    String attemptType = 'quiz',
  }) {
    final normalizedItemId = itemId.trim();
    if (normalizedItemId.isEmpty) return false;
    return _isLocallyEligibleForMastery(
      itemTopicKey: '$normalizedItemId::${topic.id}',
      topic: topic,
      attemptType: attemptType,
      occurredAt: DateTime.now(),
    );
  }

  Future<void> bindAuthenticatedUser(String? userId) {
    final inFlight = _bindingFuture;
    if (_bindingUserId == userId && inFlight != null) return inFlight;
    if (_activeUserId == userId && !_isLoading) return Future<void>.value();

    late final Future<void> future;
    future = _bindAuthenticatedUserInternal(userId).whenComplete(() {
      if (identical(_bindingFuture, future)) {
        _bindingFuture = null;
        _bindingUserId = null;
      }
    });
    _bindingUserId = userId;
    _bindingFuture = future;
    return future;
  }

  Future<void> _bindAuthenticatedUserInternal(String? userId) async {
    _activeUserId = userId;
    _errorMessage = null;

    if (userId == null) {
      _resetState();
      notifyListeners();
      return;
    }

    _resetState(keepUser: true);
    _isLoading = true;
    notifyListeners();

    await _storage.init();
    _loadLocal(userId);
    notifyListeners();

    final repository = _repository;
    if (repository == null) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      await _flushPendingCloudChanges(userId);
      await _loadRemoteState(userId, preserveLocalNewerState: true);
      if (_activeUserId != userId) return;
      _lastSyncedAt = DateTime.now();
      _errorMessage = null;
    } catch (_) {
      if (_activeUserId == userId) {
        _errorMessage =
            'Adaptive progress is using saved data on this device. Pull to refresh after your connection returns.';
      }
    } finally {
      if (_activeUserId == userId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshFromCloud() async {
    final userId = _activeUserId;
    final repository = _repository;
    if (userId == null || repository == null || _isLoading) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _flushPendingCloudChanges(userId);
      await _loadRemoteState(userId, preserveLocalNewerState: true);
      if (_activeUserId != userId) return;
      _lastSyncedAt = DateTime.now();
    } catch (_) {
      if (_activeUserId == userId) {
        _errorMessage =
            'Could not refresh adaptive progress. Your saved progress on this device is still available.';
      }
    } finally {
      if (_activeUserId == userId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Reconciles quiz scores that existed before adaptive attempt tracking.
  /// Calls are coalesced instead of dropped, so provider/content load ordering
  /// cannot permanently skip a late-arriving score/content snapshot.
  Future<void> synchronizeExistingProgress({
    required Iterable<Quiz> quizzes,
    required Map<String, int> bestScores,
  }) {
    final quizList = List<Quiz>.from(quizzes);
    final scoreMap = Map<String, int>.from(bestScores);
    final signature = _existingProgressSignature(quizList, scoreMap);
    if (signature == _lastExistingProgressSignature &&
        _existingProgressSyncFuture == null) {
      return Future<void>.value();
    }
    if (signature == _pendingExistingProgressSignature &&
        _existingProgressSyncFuture != null) {
      return _existingProgressSyncFuture!;
    }
    _pendingExistingProgressQuizzes = quizList;
    _pendingExistingProgressScores = scoreMap;
    _pendingExistingProgressSignature = signature;
    return _existingProgressSyncFuture ??= _drainExistingProgressSync();
  }

  Future<void> _drainExistingProgressSync() async {
    _isSynchronizingExistingProgress = true;
    notifyListeners();
    try {
      while (_pendingExistingProgressQuizzes != null &&
          _pendingExistingProgressScores != null) {
        final quizzes = _pendingExistingProgressQuizzes!;
        final bestScores = _pendingExistingProgressScores!;
        final signature = _pendingExistingProgressSignature;
        _pendingExistingProgressQuizzes = null;
        _pendingExistingProgressScores = null;
        _pendingExistingProgressSignature = null;
        await _synchronizeExistingProgressOnce(
          quizzes: quizzes,
          bestScores: bestScores,
        );
        _lastExistingProgressSignature = signature;
      }
    } finally {
      _existingProgressSyncFuture = null;
      _isSynchronizingExistingProgress = false;
      notifyListeners();
    }
  }

  Future<void> _synchronizeExistingProgressOnce({
    required List<Quiz> quizzes,
    required Map<String, int> bestScores,
  }) async {
    final userId = _activeUserId;
    if (userId == null) return;

    final completed = quizzes
        .where(
          (quiz) => quiz.topic != null && (bestScores[quiz.id] ?? 0) >= 100,
        )
        .toList(growable: false);
    if (completed.isEmpty) return;

    final repository = _repository;
    // Remote attempt history was already loaded by the adaptive state refresh.
    // Reuse the remembered item/topic keys instead of issuing another history
    // query every time Provider notifies about unchanged content/progress.
    final existingItemTopics = <String>{
      ..._lastCountedAttemptByItemTopic.keys,
    };
    var importedAny = false;

    for (final quiz in completed) {
      if (_activeUserId != userId) return;
      final topic = quiz.topic;
      if (topic == null) continue;
      final itemTopicKey = '${quiz.id}::${topic.id}';
      if (existingItemTopics.contains(itemTopicKey)) continue;

      final changed = await recordPracticeAttempt(
        itemId: quiz.id,
        topic: topic,
        isCorrect: true,
        attemptType: 'legacy_quiz',
        countedForMastery: true,
      );
      if (changed) {
        existingItemTopics.add(itemTopicKey);
        importedAny = true;
      }
    }

    if (importedAny && repository != null && _activeUserId == userId) {
      // One authoritative refresh after the entire legacy import batch, not
      // one full reload per imported quiz.
      await _loadRemoteState(userId, preserveLocalNewerState: true);
    }
  }

  Future<DiagnosticResult> submitDiagnostic(Map<String, int> answers) async {
    if (_diagnosticCompleted) {
      throw StateError('The diagnostic assessment has already been completed.');
    }
    if (_isSubmittingDiagnostic) {
      throw StateError('The diagnostic assessment is already being saved.');
    }
    if (answers.length < diagnosticQuestions.length) {
      throw ArgumentError('Answer every diagnostic question before submitting.');
    }

    _isSubmittingDiagnostic = true;
    _errorMessage = null;
    notifyListeners();

    var correct = 0;
    final topicResults = <LearningTopic, bool>{};
    for (final question in diagnosticQuestions) {
      final selected = answers[question.id];
      if (selected == null) {
        _isSubmittingDiagnostic = false;
        notifyListeners();
        throw ArgumentError('Answer every diagnostic question before submitting.');
      }
      final isCorrect = selected == question.correctIndex;
      if (isCorrect) correct++;
      topicResults[question.topic] = isCorrect;
    }

    final result = DiagnosticResult(
      score: ((correct / diagnosticQuestions.length) * 100).round(),
      correctAnswers: correct,
      totalQuestions: diagnosticQuestions.length,
      topicResults: topicResults,
    );

    final userId = _activeUserId;
    final repository = _repository;
    final occurredAt = DateTime.now();

    try {
      if (userId != null && repository != null) {
        final accepted = await repository.recordDiagnosticAttempt(
          userId: userId,
          result: result,
          answers: answers,
          completedAt: occurredAt,
        );
        if (_activeUserId != userId) return result;

        if (!accepted) {
          await _loadRemoteState(userId, preserveLocalNewerState: false);
          throw StateError('The diagnostic assessment has already been completed.');
        }
      }

      for (final question in diagnosticQuestions) {
        _applyEvidence(
          topic: question.topic,
          isCorrect: answers[question.id] == question.correctIndex,
          occurredAt: occurredAt,
          diagnosticEvidence: true,
        );
      }
      _diagnosticCompleted = true;

      if (userId != null) {
        await _persistLocal(userId);
        await _storage.remove(_pendingDiagnosticKey(userId));
      }
      _lastSyncedAt = repository == null ? _lastSyncedAt : DateTime.now();
      _errorMessage = null;
    } catch (error) {
      if (error is StateError) rethrow;

      // Offline/local fallback: preserve exactly one local diagnostic and queue
      // it. The cloud RPC will either accept it or reconcile to the existing
      // server diagnostic on the next refresh.
      for (final question in diagnosticQuestions) {
        _applyEvidence(
          topic: question.topic,
          isCorrect: answers[question.id] == question.correctIndex,
          occurredAt: occurredAt,
          diagnosticEvidence: true,
        );
      }
      _diagnosticCompleted = true;
      if (userId != null) {
        await _persistLocal(userId);
        await _storage.setString(
          _pendingDiagnosticKey(userId),
          jsonEncode({
            'answers': answers,
            'completed_at': occurredAt.toUtc().toIso8601String(),
          }),
        );
      }
      _errorMessage =
          'Your diagnostic is saved on this device. Pull to refresh when you are online to sync it.';
    } finally {
      _isSubmittingDiagnostic = false;
      notifyListeners();
    }
    return result;
  }

  /// Records one learning-evidence event. The server is authoritative when
  /// available: an item counts once initially and can count again only after
  /// that topic's scheduled review becomes due. Reopening/retrying cannot farm
  /// mastery. Offline mode applies the same rule against the saved schedule.
  Future<bool> recordPracticeAttempt({
    required String itemId,
    required LearningTopic topic,
    required bool isCorrect,
    String attemptType = 'quiz',
    bool countedForMastery = true,
  }) async {
    final normalizedItemId = itemId.trim();
    final normalizedType = attemptType.trim().isEmpty ? 'quiz' : attemptType.trim();
    if (normalizedItemId.isEmpty) return false;

    final occurredAt = DateTime.now();
    final key = _attemptKey(
      normalizedType,
      normalizedItemId,
      topic,
      occurredAt: occurredAt,
    );
    final itemTopicKey = '$normalizedItemId::${topic.id}';
    final userId = _activeUserId;
    final repository = _repository;
    final hasCloudAuthority = userId != null && repository != null;
    var shouldCount = countedForMastery &&
        (hasCloudAuthority ||
            _isLocallyEligibleForMastery(
              itemTopicKey: itemTopicKey,
              topic: topic,
              attemptType: normalizedType,
              occurredAt: occurredAt,
            ));
    var cloudSaved = false;

    if (userId != null && repository != null) {
      try {
        shouldCount = await repository.recordQuestionAttempt(
          userId: userId,
          itemId: normalizedItemId,
          topic: topic,
          isCorrect: isCorrect,
          attemptType: normalizedType,
          countedForMastery: countedForMastery,
          attemptedAt: occurredAt,
        );
        cloudSaved = true;
      } catch (_) {
        // When cloud saving fails, use the same local eligibility rule instead
        // of blindly counting the attempt and risking offline score farming.
        shouldCount = countedForMastery &&
            _isLocallyEligibleForMastery(
              itemTopicKey: itemTopicKey,
              topic: topic,
              attemptType: normalizedType,
              occurredAt: occurredAt,
            );
        await _queuePendingAttempt(
          userId: userId,
          itemId: normalizedItemId,
          topic: topic,
          isCorrect: isCorrect,
          attemptType: normalizedType,
          countedForMastery: countedForMastery,
          attemptedAt: occurredAt,
        );
      }
    }

    if (shouldCount) {
      _countedAttemptKeys.add(key);
      _lastCountedAttemptByItemTopic[itemTopicKey] = occurredAt;
      _applyEvidence(
        topic: topic,
        isCorrect: isCorrect,
        occurredAt: occurredAt,
      );
    }

    if (userId != null) await _persistLocal(userId);
    notifyListeners();

    if (userId != null && repository != null && cloudSaved) {
      // The local evidence update is immediate. Do not reload the whole
      // adaptive history after every single answer; screens already perform an
      // authoritative refresh at session completion or explicit pull-to-refresh.
      _lastSyncedAt = DateTime.now();
      _errorMessage = null;
    } else if (userId != null && repository != null && !cloudSaved) {
      _errorMessage =
          'Your latest attempt is saved on this device. Pull to refresh when you are online to sync it.';
    }

    notifyListeners();
    return shouldCount;
  }

  bool _isLocallyEligibleForMastery({
    required String itemTopicKey,
    required LearningTopic topic,
    required String attemptType,
    required DateTime occurredAt,
  }) {
    final last = _lastCountedAttemptByItemTopic[itemTopicKey];
    if (last == null) return true;
    if (attemptType == 'legacy_quiz') return false;

    final dueAt = masteryFor(topic).nextReviewAt;
    if (dueAt == null || occurredAt.isBefore(dueAt)) return false;
    return last.isBefore(dueAt);
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _loadRemoteState(
    String userId, {
    required bool preserveLocalNewerState,
  }) async {
    final repository = _repository;
    if (repository == null) return;

    // New databases repair + return the compact adaptive snapshot in one RPC.
    // Older databases automatically fall back inside the repository to the
    // previous repair + parallel-read path until the migration is applied.
    final remoteState = await repository.fetchAdaptiveState(userId);
    final remoteMastery = remoteState.mastery;
    final diagnostics = remoteState.diagnostics;
    final countedAttempts = remoteState.countedAttempts;
    if (_activeUserId != userId) return;

    final rebuilt = remoteState.canonical
        ? const <LearningTopic, TopicMastery>{}
        : _rebuildFromHistory(diagnostics, countedAttempts);
    final hasHistory = diagnostics.isNotEmpty || countedAttempts.isNotEmpty;
    final remoteByTopic = {
      for (final item in remoteMastery) item.topic: item,
    };
    final hasPendingDiagnostic =
        _storage.getString(_pendingDiagnosticKey(userId)).isNotEmpty;
    final hasPendingLocal =
        _storage.getString(_pendingAttemptsKey(userId)).isNotEmpty ||
        hasPendingDiagnostic;

    for (final topic in LearningTopic.values) {
      var chosen = remoteState.canonical
          ? remoteByTopic[topic] ?? TopicMastery.initial(topic)
          : hasHistory
              ? rebuilt[topic] ?? TopicMastery.initial(topic)
              : remoteByTopic[topic] ?? TopicMastery.initial(topic);

      // History is the canonical source whenever it exists. Aggregate rows
      // may have been produced by an older buggy build and must not override
      // a clean reconstruction. Local state is preserved only when there are
      // unsynced changes waiting to be uploaded.
      if (preserveLocalNewerState && hasPendingLocal) {
        final local = _mastery[topic];
        if (local != null && local.attempts > chosen.attempts) {
          chosen = local;
        }
      }
      _mastery[topic] = chosen;
    }

    _rememberRemoteAttemptState(countedAttempts);
    if (hasPendingLocal) {
      _loadLocalCountedKeys(userId, merge: true);
    }
    // Once cloud state is available, a stale legacy local flag must not claim
    // the diagnostic exists. Preserve local completion only while a real
    // offline diagnostic payload is still waiting to sync.
    _diagnosticCompleted = remoteState.diagnosticCompleted ||
        diagnostics.isNotEmpty ||
        (hasPendingDiagnostic && _diagnosticCompleted);

    await _persistLocal(userId);
  }

  void _rememberRemoteAttemptState(
    Iterable<AdaptiveQuestionAttemptRecord> attempts,
  ) {
    _countedAttemptKeys
      ..clear()
      ..addAll(attempts.map((attempt) => attempt.masteryKey));
    _lastCountedAttemptByItemTopic.clear();
    for (final attempt in attempts.where((item) => item.countedForMastery)) {
      final key = attempt.itemTopicKey;
      final previous = _lastCountedAttemptByItemTopic[key];
      if (previous == null || attempt.attemptedAt.isAfter(previous)) {
        _lastCountedAttemptByItemTopic[key] = attempt.attemptedAt;
      }
    }
  }

  Map<LearningTopic, TopicMastery> _rebuildFromHistory(
    List<DiagnosticAttemptRecord> diagnostics,
    List<AdaptiveQuestionAttemptRecord> attempts,
  ) {
    final result = _initialMastery();
    final events = <_EvidenceEvent>[];

    for (final diagnostic in diagnostics) {
      for (var index = 0; index < diagnosticQuestions.length; index++) {
        final question = diagnosticQuestions[index];
        final selected = diagnostic.answers[question.id];
        if (selected == null) continue;
        events.add(
          _EvidenceEvent(
            topic: question.topic,
            isCorrect: selected == question.correctIndex,
            occurredAt: diagnostic.completedAt.add(
              Duration(microseconds: index),
            ),
            diagnosticEvidence: true,
          ),
        );
      }
    }

    for (final attempt in attempts.where((item) => item.countedForMastery)) {
      events.add(
        _EvidenceEvent(
          topic: attempt.topic,
          isCorrect: attempt.isCorrect,
          occurredAt: attempt.attemptedAt,
        ),
      );
    }

    events.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    for (final event in events) {
      final current = result[event.topic] ?? TopicMastery.initial(event.topic);
      result[event.topic] = _masteryAfterEvidence(
        current: current,
        isCorrect: event.isCorrect,
        occurredAt: event.occurredAt,
        diagnosticEvidence: event.diagnosticEvidence,
      );
    }
    return result;
  }

  void _applyEvidence({
    required LearningTopic topic,
    required bool isCorrect,
    required DateTime occurredAt,
    bool diagnosticEvidence = false,
  }) {
    final current = masteryFor(topic);
    _mastery[topic] = _masteryAfterEvidence(
      current: current,
      isCorrect: isCorrect,
      occurredAt: occurredAt,
      diagnosticEvidence: diagnosticEvidence,
    );
  }

  TopicMastery _masteryAfterEvidence({
    required TopicMastery current,
    required bool isCorrect,
    required DateTime occurredAt,
    required bool diagnosticEvidence,
  }) {
    final nextAttempts = current.attempts + 1;
    final nextCorrect = current.correctAnswers + (isCorrect ? 1 : 0);
    final nextMastery = current.attempts == 0
        ? diagnosticEvidence
              ? (isCorrect ? 70 : 30)
              : (isCorrect ? 65 : 35)
        : _calculateMastery(current, isCorrect);
    return current.copyWith(
      mastery: nextMastery,
      attempts: nextAttempts,
      correctAnswers: nextCorrect,
      lastPracticedAt: occurredAt,
      nextReviewAt: _nextReviewDate(nextMastery, occurredAt),
    );
  }

  int _calculateMastery(TopicMastery current, bool isCorrect) {
    final target = isCorrect ? 100 : 0;
    final value = (current.mastery * 0.75 + target * 0.25).round();
    return value.clamp(0, 100).toInt();
  }

  DateTime _nextReviewDate(int mastery, DateTime from) {
    final days = switch (mastery) {
      < 40 => 1,
      < 60 => 2,
      < 80 => 4,
      _ => 7,
    };
    return from.add(Duration(days: days));
  }

  Future<void> _syncAggregateState(String userId) async {
    final repository = _repository;
    if (repository == null || _activeUserId != userId) return;
    await repository.rebuildAdaptiveMastery(userId);
    _lastSyncedAt = DateTime.now();
  }

  Future<void> _flushPendingCloudChanges(String userId) async {
    final repository = _repository;
    if (repository == null || _activeUserId != userId) return;

    final pendingDiagnostic = _storage.getString(_pendingDiagnosticKey(userId));
    if (pendingDiagnostic.isNotEmpty) {
      try {
        final decoded = jsonDecode(pendingDiagnostic);
        if (decoded is Map) {
          final rawAnswers = decoded['answers'] is Map
              ? Map<String, dynamic>.from(decoded['answers'] as Map)
              : Map<String, dynamic>.from(decoded);
          final answers = <String, int>{};
          for (final entry in rawAnswers.entries) {
            final value = entry.value;
            if (value is num) answers[entry.key.toString()] = value.toInt();
          }
          final completedAt = DateTime.tryParse(
            decoded['completed_at']?.toString() ?? '',
          );
          if (answers.length == diagnosticQuestions.length) {
            final result = _diagnosticResultFromAnswers(answers);
            await repository.recordDiagnosticAttempt(
              userId: userId,
              result: result,
              answers: answers,
              completedAt: completedAt,
            );
          }
        }
        await _storage.remove(_pendingDiagnosticKey(userId));
      } catch (_) {
        // Leave the pending diagnostic for a later refresh.
      }
    }

    final pendingRaw = _storage.getString(_pendingAttemptsKey(userId));
    if (pendingRaw.isEmpty) return;
    try {
      final decoded = jsonDecode(pendingRaw);
      if (decoded is! List) return;
      final remaining = <Map<String, dynamic>>[];
      for (final raw in decoded.whereType<Map>()) {
        final map = Map<String, dynamic>.from(raw);
        final topic = LearningTopicX.fromId(map['topic_id']?.toString());
        if (topic == null) continue;
        try {
          final attemptedAt = DateTime.tryParse(
            map['attempted_at']?.toString() ?? '',
          );
          await repository.recordQuestionAttempt(
            userId: userId,
            itemId: map['item_id']?.toString() ?? '',
            topic: topic,
            isCorrect: map['is_correct'] == true,
            attemptType: map['attempt_type']?.toString() ?? 'quiz',
            countedForMastery: map['counted_for_mastery'] == true,
            attemptedAt: attemptedAt,
          );
        } catch (_) {
          remaining.add(map);
        }
      }
      if (remaining.isEmpty) {
        await _storage.remove(_pendingAttemptsKey(userId));
      } else {
        await _storage.setString(
          _pendingAttemptsKey(userId),
          jsonEncode(remaining),
        );
      }
      await _syncAggregateState(userId);
    } catch (_) {
      // Keep malformed/temporarily unavailable pending data untouched.
    }
  }

  DiagnosticResult _diagnosticResultFromAnswers(Map<String, int> answers) {
    var correct = 0;
    final topicResults = <LearningTopic, bool>{};
    for (final question in diagnosticQuestions) {
      final isCorrect = answers[question.id] == question.correctIndex;
      if (isCorrect) correct++;
      topicResults[question.topic] = isCorrect;
    }
    return DiagnosticResult(
      score: ((correct / diagnosticQuestions.length) * 100).round(),
      correctAnswers: correct,
      totalQuestions: diagnosticQuestions.length,
      topicResults: topicResults,
    );
  }

  Future<void> _queuePendingAttempt({
    required String userId,
    required String itemId,
    required LearningTopic topic,
    required bool isCorrect,
    required String attemptType,
    required bool countedForMastery,
    required DateTime attemptedAt,
  }) async {
    final key = _pendingAttemptsKey(userId);
    final pending = <Map<String, dynamic>>[];
    final raw = _storage.getString(key);
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          pending.addAll(
            decoded.whereType<Map>().map(
              (item) => Map<String, dynamic>.from(item),
            ),
          );
        }
      } catch (_) {
        // Start a clean queue when the previous local payload is malformed.
      }
    }
    pending.add({
      'item_id': itemId,
      'topic_id': topic.id,
      'is_correct': isCorrect,
      'attempt_type': attemptType,
      'counted_for_mastery': countedForMastery,
      'attempted_at': attemptedAt.toUtc().toIso8601String(),
    });
    await _storage.setString(key, jsonEncode(pending));
  }

  void _loadLocal(String userId) {
    var raw = _storage.getString(_masteryKey(userId));
    if (raw.isEmpty) {
      raw = _storage.getString('user:$userId:adaptiveMasteryV2');
    }
    if (raw.isEmpty) {
      raw = _storage.getString('user:$userId:adaptiveMasteryV1');
    }
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final value in decoded.whereType<Map>()) {
            final item = TopicMastery.fromMap(
              Map<String, dynamic>.from(value),
            );
            _mastery[item.topic] = item;
          }
        }
      } catch (_) {
        // Ignore malformed local adaptive data and keep safe defaults.
      }
    }
    final currentDiagnostic =
        _storage.getInt(_diagnosticKey(userId), defaultValue: 0) == 1;
    final v2Diagnostic =
        _storage.getInt(
          'user:$userId:diagnosticCompleteV2',
          defaultValue: 0,
        ) ==
        1;
    final legacyDiagnostic =
        _storage.getInt(
          'user:$userId:diagnosticCompleteV1',
          defaultValue: 0,
        ) ==
        1;
    _diagnosticCompleted =
        currentDiagnostic || v2Diagnostic || legacyDiagnostic;
    _loadLocalCountedKeys(userId);
  }

  void _loadLocalCountedKeys(String userId, {bool merge = false}) {
    if (!merge) {
      _countedAttemptKeys.clear();
      _lastCountedAttemptByItemTopic.clear();
    }
    _countedAttemptKeys.addAll(
      _storage.getStringList(_countedAttemptsKey(userId)),
    );

    // V3 stored counted keys before V4 started storing exact item timestamps.
    // Recover enough metadata from those keys so an offline upgrade cannot
    // treat a previously counted item as brand-new and farm it once more.
    for (final countedKey in _countedAttemptKeys) {
      final parts = countedKey.split('::');
      if (parts.length < 3) continue;
      final itemId = parts[1].trim();
      final topic = LearningTopicX.fromId(parts[2]);
      if (itemId.isEmpty || topic == null) continue;
      DateTime? recovered;
      if (parts.length >= 4) {
        recovered = DateTime.tryParse('${parts[3]}T00:00:00+08:00');
      }
      recovered ??= masteryFor(topic).lastPracticedAt;
      recovered ??= DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final itemTopicKey = '$itemId::${topic.id}';
      final previous = _lastCountedAttemptByItemTopic[itemTopicKey];
      if (previous == null || recovered.isAfter(previous)) {
        _lastCountedAttemptByItemTopic[itemTopicKey] = recovered;
      }
    }

    final rawLast = _storage.getString(_lastCountedAttemptsKey(userId));
    if (rawLast.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawLast);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final parsed = DateTime.tryParse(entry.value?.toString() ?? '');
            if (parsed == null) continue;
            final key = entry.key.toString();
            final previous = _lastCountedAttemptByItemTopic[key];
            if (previous == null || parsed.isAfter(previous)) {
              _lastCountedAttemptByItemTopic[key] = parsed;
            }
          }
        }
      } catch (_) {
        // Ignore malformed legacy local metadata.
      }
    }
  }

  Future<void> _persistLocal(String userId) async {
    await _storage.setString(
      _masteryKey(userId),
      jsonEncode(_mastery.values.map((item) => item.toMap()).toList()),
    );
    await _storage.setInt(_diagnosticKey(userId), _diagnosticCompleted ? 1 : 0);
    await _storage.setStringList(
      _countedAttemptsKey(userId),
      _countedAttemptKeys.toList(growable: false),
    );
    await _storage.setString(
      _lastCountedAttemptsKey(userId),
      jsonEncode({
        for (final entry in _lastCountedAttemptByItemTopic.entries)
          entry.key: entry.value.toUtc().toIso8601String(),
      }),
    );
  }

  String _existingProgressSignature(
    List<Quiz> quizzes,
    Map<String, int> bestScores,
  ) {
    final parts = quizzes
        .where((quiz) => quiz.topic != null && (bestScores[quiz.id] ?? 0) >= 100)
        .map((quiz) => '${quiz.id}:${quiz.topic!.id}:${bestScores[quiz.id] ?? 0}')
        .toList(growable: false)
      ..sort();
    return parts.join('|');
  }

  void _resetState({bool keepUser = false}) {
    _mastery = _initialMastery();
    _countedAttemptKeys.clear();
    _lastCountedAttemptByItemTopic.clear();
    _diagnosticCompleted = false;
    _lastSyncedAt = null;
    _isLoading = false;
    _isSubmittingDiagnostic = false;
    _isSynchronizingExistingProgress = false;
    _pendingExistingProgressQuizzes = null;
    _pendingExistingProgressScores = null;
    _pendingExistingProgressSignature = null;
    _lastExistingProgressSignature = null;
    if (!keepUser) _activeUserId = null;
  }

  String _attemptKey(
    String attemptType,
    String itemId,
    LearningTopic topic, {
    DateTime? occurredAt,
  }) {
    final base = '${attemptType.trim()}::${itemId.trim()}::${topic.id}';
    if (attemptType.trim() == 'legacy_quiz') return base;
    return '$base::${philippinesDayKey(occurredAt ?? DateTime.now())}';
  }

  String _masteryKey(String userId) => 'user:$userId:adaptiveMasteryV3';
  String _diagnosticKey(String userId) => 'user:$userId:diagnosticCompleteV3';
  String _countedAttemptsKey(String userId) =>
      'user:$userId:adaptiveCountedAttemptsV3';
  String _lastCountedAttemptsKey(String userId) =>
      'user:$userId:adaptiveLastCountedAttemptsV4';
  String _pendingAttemptsKey(String userId) =>
      'user:$userId:adaptivePendingAttemptsV3';
  String _pendingDiagnosticKey(String userId) =>
      'user:$userId:adaptivePendingDiagnosticV3';
}

Map<LearningTopic, TopicMastery> _initialMastery() => {
  for (final topic in LearningTopic.values) topic: TopicMastery.initial(topic),
};

class _EvidenceEvent {
  final LearningTopic topic;
  final bool isCorrect;
  final DateTime occurredAt;
  final bool diagnosticEvidence;

  const _EvidenceEvent({
    required this.topic,
    required this.isCorrect,
    required this.occurredAt,
    this.diagnosticEvidence = false,
  });
}
