import 'package:flutter/foundation.dart';

import '../../data/models/learning_progression.dart';
import '../../data/models/learning_topic.dart';
import '../../data/repositories/learning_progression_repository.dart';

class LearningProgressionController extends ChangeNotifier {
  final LearningProgressionRepository? _repository;

  LearningProgressionController({LearningProgressionRepository? repository})
    : _repository = repository;

  String? _activeUserId;
  int _requestEpoch = 0;
  bool _disposed = false;
  bool _isLoading = false;
  bool _isStartingSession = false;
  bool _isSubmittingAnswer = false;
  bool _isCompletingSession = false;
  bool _hasLoaded = false;
  DateTime? _lastLoadedAt;
  Future<void>? _refreshFuture;
  String? _errorMessage;
  List<LearningObjective> _objectives = const [];
  Map<LearningTopic, LearnerTopicRank> _ranks = {
    for (final topic in LearningTopic.values)
      topic: LearnerTopicRank.initial(topic),
  };
  KnowledgeCheckSession? _session;
  int _questionIndex = 0;
  final Map<String, int> _selectedAnswers = <String, int>{};
  final Map<String, KnowledgeAnswerFeedback> _feedback =
      <String, KnowledgeAnswerFeedback>{};
  KnowledgeCheckSummary? _summary;

  String? get activeUserId => _activeUserId;
  bool get isLoading => _isLoading;
  bool get isStartingSession => _isStartingSession;
  bool get isSubmittingAnswer => _isSubmittingAnswer;
  bool get isCompletingSession => _isCompletingSession;
  bool get hasLoaded => _hasLoaded;
  DateTime? get lastLoadedAt => _lastLoadedAt;
  String? get errorMessage => _errorMessage;
  List<LearningObjective> get objectives => List.unmodifiable(_objectives);
  Map<LearningTopic, LearnerTopicRank> get ranks => Map.unmodifiable(_ranks);
  KnowledgeCheckSession? get session => _session;
  KnowledgeCheckSummary? get summary => _summary;
  int get questionIndex => _questionIndex;
  Map<String, int> get selectedAnswers => Map.unmodifiable(_selectedAnswers);
  Map<String, KnowledgeAnswerFeedback> get feedback =>
      Map.unmodifiable(_feedback);

  bool get hasActiveSession => _session != null && _summary == null;
  bool get isSessionComplete => _summary != null;

  KnowledgeCheckQuestion? get currentQuestion {
    final current = _session;
    if (current == null || current.questions.isEmpty) return null;
    if (_questionIndex < 0 || _questionIndex >= current.questions.length) {
      return null;
    }
    return current.questions[_questionIndex];
  }

  int get answeredCount => _feedback.length;

  LearnerTopicRank rankFor(LearningTopic topic) =>
      _ranks[topic] ?? LearnerTopicRank.initial(topic);

  LearningRank get overallRank {
    // Balanced progression: the overall rank follows the learner's weakest
    // competency rank, so one highly practiced topic cannot hide a major gap.
    var minimum = LearningRank.expert;
    for (final topic in LearningTopic.values) {
      final rank = rankFor(topic).rank;
      if (rank.level < minimum.level) minimum = rank;
    }
    return minimum;
  }

  int get overallTier {
    final weakestLevel = overallRank.level;
    final tiers = LearningTopic.values
        .map(rankFor)
        .where((item) => item.rank.level == weakestLevel)
        .map((item) => item.tier)
        .toList(growable: false);
    if (tiers.isEmpty) return 1;
    return tiers.reduce((a, b) => a < b ? a : b);
  }

  String get overallRankLabel =>
      '${overallRank.label} ${_romanTier(overallTier)}';

  List<LearningObjective> objectivesForContent(String contentItemId) {
    final result = _objectives
        .where((item) => item.contentItemId == contentItemId)
        .toList(growable: false);
    result.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return result;
  }

  Future<void> bindAuthenticatedUser(String? userId) async {
    if (_disposed) return;
    if (_activeUserId == userId) return;
    _activeUserId = userId;
    _requestEpoch++;
    _isLoading = false;
    _isStartingSession = false;
    _isSubmittingAnswer = false;
    _isCompletingSession = false;
    _clearSession(notify: false);
    _hasLoaded = false;
    _lastLoadedAt = null;
    _refreshFuture = null;
    // Rank/progress data is account-specific. Clear it on every account switch
    // so lazy loading never exposes the previous learner's cached state.
    _ranks = {
      for (final topic in LearningTopic.values)
        topic: LearnerTopicRank.initial(topic),
    };
    _errorMessage = null;
    if (userId == null) {
      // Objectives are global/published content and can otherwise stay cached
      // between authenticated users. Clear them only when the session ends.
      _objectives = const [];
    }
    // Progression data is intentionally lazy because it is only needed on the
    // learning-path/practice flows, not on every sign-in.
    notifyListeners();
  }

  Future<void> ensureLoaded({
    Duration maxAge = const Duration(minutes: 5),
  }) async {
    final last = _lastLoadedAt;
    if (_hasLoaded &&
        last != null &&
        DateTime.now().difference(last) < maxAge) {
      return;
    }
    await refresh(force: false);
  }

  Future<void> refresh({bool force = true}) {
    if (_disposed) return Future<void>.value();
    final existing = _refreshFuture;
    if (existing != null) return existing;

    final userId = _activeUserId;
    final epoch = _requestEpoch;
    final repository = _repository;
    if (userId == null || repository == null) return Future<void>.value();
    if (!force &&
        _hasLoaded &&
        _lastLoadedAt != null &&
        DateTime.now().difference(_lastLoadedAt!) <
            const Duration(minutes: 5)) {
      return Future<void>.value();
    }

    late final Future<void> future;
    future = _refreshInternal(userId, epoch, repository).whenComplete(() {
      if (identical(_refreshFuture, future)) _refreshFuture = null;
    });
    _refreshFuture = future;
    return future;
  }

  Future<void> _refreshInternal(
    String userId,
    int epoch,
    LearningProgressionRepository repository,
  ) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await repository.refreshProgression();
      final results = await Future.wait<dynamic>([
        repository.fetchObjectives(),
        repository.fetchTopicRanks(userId),
      ]);
      if (!_isCurrent(userId, epoch)) return;
      _objectives = List<LearningObjective>.from(results[0] as List);
      final fetchedRanks = List<LearnerTopicRank>.from(results[1] as List);
      _ranks = {
        for (final topic in LearningTopic.values)
          topic: LearnerTopicRank.initial(topic),
        for (final item in fetchedRanks) item.topic: item,
      };
      _hasLoaded = true;
      _lastLoadedAt = DateTime.now();
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Learning progression refresh failed: $error\n$stackTrace');
      }
      if (_isCurrent(userId, epoch)) {
        _errorMessage =
            'Learning progression could not be refreshed. Try again when your connection is stable.';
      }
    } finally {
      if (_isCurrent(userId, epoch)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> startAdaptiveSession({
    int questionCount = 10,
    LearningTopic? focusTopic,
    String mode = 'adaptive',
  }) async {
    final repository = _repository;
    final userId = _activeUserId;
    final epoch = _requestEpoch;
    if (userId == null || repository == null || _isStartingSession) {
      return false;
    }

    _isStartingSession = true;
    _errorMessage = null;
    _clearSession(notify: false);
    notifyListeners();
    try {
      final session = await repository.createKnowledgeCheck(
        questionCount: questionCount,
        focusTopic: focusTopic,
        mode: mode,
      );
      if (!_isCurrent(userId, epoch)) return false;
      _session = session;
      _questionIndex = 0;
      return true;
    } catch (error) {
      if (_isCurrent(userId, epoch)) {
        _errorMessage = _friendlyMessage(error);
      }
      return false;
    } finally {
      if (_isCurrent(userId, epoch)) {
        _isStartingSession = false;
        notifyListeners();
      }
    }
  }

  Future<KnowledgeAnswerFeedback?> submitAnswer(int selectedIndex) async {
    final repository = _repository;
    final currentSession = _session;
    final question = currentQuestion;
    final userId = _activeUserId;
    final epoch = _requestEpoch;
    if (repository == null ||
        currentSession == null ||
        question == null ||
        userId == null ||
        _isSubmittingAnswer ||
        _feedback.containsKey(question.id)) {
      return null;
    }
    if (selectedIndex < 0 || selectedIndex >= question.options.length) {
      return null;
    }

    _isSubmittingAnswer = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await repository.answerQuestion(
        sessionId: currentSession.id,
        questionId: question.id,
        selectedIndex: selectedIndex,
      );
      if (!_isCurrent(userId, epoch) ||
          _session?.id != currentSession.id ||
          currentQuestion?.id != question.id) {
        return null;
      }
      _selectedAnswers[question.id] = selectedIndex;
      _feedback[question.id] = result;
      return result;
    } catch (error) {
      if (_isCurrent(userId, epoch)) {
        _errorMessage = _friendlyMessage(error);
      }
      return null;
    } finally {
      if (_isCurrent(userId, epoch)) {
        _isSubmittingAnswer = false;
        notifyListeners();
      }
    }
  }

  Future<bool> nextQuestionOrComplete() async {
    final currentSession = _session;
    final question = currentQuestion;
    if (currentSession == null || question == null) return false;
    if (!_feedback.containsKey(question.id)) return false;

    if (_questionIndex < currentSession.questions.length - 1) {
      _questionIndex += 1;
      notifyListeners();
      return true;
    }
    return completeSession();
  }

  void previousQuestion() {
    if (_questionIndex <= 0) return;
    _questionIndex -= 1;
    notifyListeners();
  }

  Future<bool> completeSession() async {
    final repository = _repository;
    final current = _session;
    final userId = _activeUserId;
    final epoch = _requestEpoch;
    if (repository == null ||
        current == null ||
        userId == null ||
        _isCompletingSession) {
      return false;
    }
    if (_feedback.length < current.questions.length) return false;

    _isCompletingSession = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await repository.completeKnowledgeCheck(current.id);
      if (!_isCurrent(userId, epoch) || _session?.id != current.id) {
        return false;
      }
      _summary = result;
      if (result.ranks.isNotEmpty) {
        _ranks = {
          for (final topic in LearningTopic.values)
            topic: result.ranks[topic] ?? rankFor(topic),
        };
      }
      _hasLoaded = true;
      _lastLoadedAt = DateTime.now();
      return true;
    } catch (error) {
      if (_isCurrent(userId, epoch)) {
        _errorMessage = _friendlyMessage(error);
      }
      return false;
    } finally {
      if (_isCurrent(userId, epoch)) {
        _isCompletingSession = false;
        notifyListeners();
      }
    }
  }

  Future<void> abandonSession() async {
    final current = _session;
    final repository = _repository;
    final userId = _activeUserId;
    final epoch = _requestEpoch;
    if (current == null) {
      _clearSession(notify: true);
      return;
    }
    if (repository != null && _summary == null) {
      try {
        await repository.abandonKnowledgeCheck(current.id);
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('Knowledge-check abandon failed: $error\n$stackTrace');
        }
        // Leaving the page must still be possible if the connection drops.
        // A future session start also closes stale active sessions server-side.
      }
    }
    if (userId != null && !_isCurrent(userId, epoch)) return;
    _clearSession(notify: true);
  }

  void clearSession() => _clearSession(notify: true);

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  void _clearSession({required bool notify}) {
    _session = null;
    _questionIndex = 0;
    _selectedAnswers.clear();
    _feedback.clear();
    _summary = null;
    if (notify) notifyListeners();
  }

  bool _isCurrent(String userId, int epoch) =>
      !_disposed && _activeUserId == userId && _requestEpoch == epoch;

  @override
  void dispose() {
    _disposed = true;
    _requestEpoch++;
    super.dispose();
  }

  String _friendlyMessage(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('no eligible') || text.contains('no question')) {
      return 'No adaptive questions are available for this learning state yet.';
    }
    if (text.contains('socket') ||
        text.contains('network') ||
        text.contains('connection')) {
      return 'Adaptive Knowledge Checks need an internet connection so answers can be verified safely.';
    }
    return 'The knowledge check could not continue. Please try again.';
  }
}

String _romanTier(int tier) => switch (tier.clamp(1, 3)) {
  1 => 'I',
  2 => 'II',
  _ => 'III',
};
