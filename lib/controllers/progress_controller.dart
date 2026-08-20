import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/user_progress.dart';
import '../repositories/progress_repository.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';

enum ProgressSyncState { localOnly, syncing, synced, error }

class ProgressController extends ChangeNotifier {
  ProgressController({
    required List<String> lessonIds,
    required List<String> quizIds,
    StorageService? storage,
    ProgressRepository? remoteRepository,
  }) : _lessonIds = List<String>.unmodifiable(lessonIds),
       _quizIds = List<String>.unmodifiable(quizIds),
       _storage = storage ?? StorageService(),
       _remoteRepository = remoteRepository,
       _progress = UserProgress.initial(totalLessons: lessonIds.length);

  static const _completedLessonsKey = 'completedLessonIds';
  static const _legacyQuizScoreKey = 'quizScore';
  static const _quizBestScoresKey = 'quizBestScoresV2';
  static const _badgesKey = 'badges';
  static const _knowledgeLevelKey = 'knowledgeLevel';
  static const _legacyProgressOwnerKey = 'legacyProgressOwnerUserId';

  List<String> _lessonIds;
  List<String> _quizIds;
  final StorageService _storage;
  final ProgressRepository? _remoteRepository;

  UserProgress _progress;
  bool _isLoading = false;
  bool _isInitialized = false;
  Future<void>? _initializationFuture;
  String? _errorMessage;
  String? _activeUserId;
  DateTime? _lastSyncedAt;
  ProgressSyncState _syncState = ProgressSyncState.localOnly;

  UserProgress get progress => _progress;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;
  int get maximumQuizScore => _quizIds.length * 100;
  int get currentQuizScore => _quizIds.fold<int>(
    0,
    (total, id) => total + (_progress.quizBestScores[id] ?? 0),
  );
  String? get activeUserId => _activeUserId;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  ProgressSyncState get syncState => _syncState;
  bool get isCloudSyncEnabled =>
      _activeUserId != null && _remoteRepository != null;

  Future<void> init() {
    if (_isInitialized) return Future<void>.value();
    return _initializationFuture ??= _performInit();
  }

  Future<void> _performInit() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _storage.init();
      _progress = _readLocalProgress(prefix: '');
      _updateLevelInMemory();
      await _persistLocal(prefix: '', clearLegacyScore: true);
    } catch (_) {
      _errorMessage =
          'Your progress could not be loaded. You can continue, but changes may not be saved on this device.';
    } finally {
      _isLoading = false;
      _isInitialized = true;
      notifyListeners();
    }
  }

  void updateContentIds({
    required List<String> lessonIds,
    required List<String> quizIds,
  }) {
    final normalizedLessons = lessonIds.toSet().toList(growable: false);
    final normalizedQuizzes = quizIds.toSet().toList(growable: false);
    if (listEquals(_lessonIds, normalizedLessons) &&
        listEquals(_quizIds, normalizedQuizzes)) {
      return;
    }

    _lessonIds = normalizedLessons;
    _quizIds = normalizedQuizzes;
    _progress = _sanitizeProgress(
      UserProgress(
        completedLessonIds: _progress.completedLessonIds,
        totalLessons: _lessonIds.length,
        quizBestScores: _progress.quizBestScores,
        badges: _progress.badges,
        knowledgeLevel: _progress.knowledgeLevel,
      ),
    );
    _updateLevelInMemory();
    scheduleMicrotask(notifyListeners);
  }

  Future<void> bindAuthenticatedUser(String? userId) async {
    await init();
    if (_activeUserId == userId) return;

    _activeUserId = userId;
    if (userId == null) {
      _progress = UserProgress.initial(totalLessons: _lessonIds.length);
      _syncState = ProgressSyncState.localOnly;
      _lastSyncedAt = null;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _syncState = _remoteRepository == null
        ? ProgressSyncState.localOnly
        : ProgressSyncState.syncing;
    _errorMessage = null;
    notifyListeners();

    final prefix = _prefixFor(userId);
    try {
      final accountLocal = _readLocalProgress(prefix: prefix);
      final legacyOwner = _storage.getString(_legacyProgressOwnerKey);
      final canMigrateLegacy = legacyOwner.isEmpty || legacyOwner == userId;
      final legacyLocal = canMigrateLegacy
          ? _readLocalProgress(prefix: '')
          : UserProgress.initial(totalLessons: _lessonIds.length);
      var merged = _mergeProgress(accountLocal, legacyLocal);

      _progress = _sanitizeProgress(merged);
      _updateLevelInMemory();
      await _persistLocal(prefix: prefix);
      if (legacyOwner.isEmpty) {
        await _storage.setString(_legacyProgressOwnerKey, userId);
      }

      final remote = _remoteRepository == null
          ? null
          : await _remoteRepository.fetchProgress(
              userId: userId,
              totalLessons: _lessonIds.length,
            );
      if (_activeUserId != userId) return;

      if (remote != null) merged = _mergeProgress(merged, remote);
      _progress = _sanitizeProgress(merged);
      _updateLevelInMemory();
      await _persistLocal(prefix: prefix);

      if (_remoteRepository != null) {
        await _remoteRepository.upsertProgress(
          userId: userId,
          progress: _progress,
        );
        if (_activeUserId != userId) return;
        _syncState = ProgressSyncState.synced;
        _lastSyncedAt = DateTime.now();
      }
    } catch (_) {
      if (_activeUserId != userId) return;
      _progress = _sanitizeProgress(_readLocalProgress(prefix: prefix));
      _updateLevelInMemory();
      _syncState = ProgressSyncState.error;
      _errorMessage =
          'You appear to be offline. Your progress is saved on this device and will update online after you reconnect.';
    } finally {
      if (_activeUserId == userId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> retryInit() async {
    if (_activeUserId != null) {
      final userId = _activeUserId!;
      _activeUserId = null;
      await bindAuthenticatedUser(userId);
      return;
    }
    _isInitialized = false;
    _initializationFuture = null;
    await init();
  }

  Future<void> refreshFromCloud() async {
    final userId = _activeUserId;
    final repository = _remoteRepository;
    if (userId == null || repository == null || _isLoading) return;

    _isLoading = true;
    _syncState = ProgressSyncState.syncing;
    _errorMessage = null;
    notifyListeners();

    try {
      final remote = await repository.fetchProgress(
        userId: userId,
        totalLessons: _lessonIds.length,
      );
      if (_activeUserId != userId) return;
      if (remote != null) {
        _progress = _sanitizeProgress(_mergeProgress(_progress, remote));
        _updateLevelInMemory();
        await _persistLocal(prefix: _prefixFor(userId));
      }
      _syncState = ProgressSyncState.synced;
      _lastSyncedAt = DateTime.now();
    } catch (_) {
      if (_activeUserId == userId) {
        _syncState = ProgressSyncState.error;
        _errorMessage =
            'Your saved progress is available, but the latest online progress could not be refreshed.';
      }
    } finally {
      if (_activeUserId == userId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  bool isLessonCompleted(String lessonId) =>
      _progress.completedLessonIds.contains(lessonId);
  bool hasBadge(String badgeId) => _progress.badges.contains(badgeId);
  int bestScoreForQuiz(String quizId) => _progress.quizBestScores[quizId] ?? 0;

  Future<void> completeLesson(String lessonId) async {
    final normalizedId = lessonId.trim();
    if (!_lessonIds.contains(normalizedId) || isLessonCompleted(normalizedId)) {
      return;
    }

    final completed = List<String>.from(_progress.completedLessonIds)
      ..add(normalizedId);
    final badges = List<String>.from(_progress.badges);
    if (completed.length == 1 && !badges.contains(ProgressBadges.aiExplorer)) {
      badges.add(ProgressBadges.aiExplorer);
    }
    _progress = _progress.copyWith(
      completedLessonIds: completed,
      badges: badges,
    );
    _updateLevelInMemory();
    notifyListeners();
    await _persistProgress();
  }

  Future<bool> recordQuizResult({
    required String quizId,
    required bool isCorrect,
  }) async {
    if (!isCorrect || !_quizIds.contains(quizId)) return false;
    if (bestScoreForQuiz(quizId) >= 100) return false;

    final scores = Map<String, int>.from(_progress.quizBestScores)
      ..[quizId] = 100;
    final badges = List<String>.from(_progress.badges);
    if (!badges.contains(ProgressBadges.quizAce)) {
      badges.add(ProgressBadges.quizAce);
    }
    _progress = _progress.copyWith(quizBestScores: scores, badges: badges);
    _updateLevelInMemory();
    notifyListeners();
    await _persistProgress();
    return true;
  }

  Future<void> addGameBadge() => _addBadge(ProgressBadges.aiDetective);
  Future<void> addSandboxBadge() => _addBadge(ProgressBadges.promptImprover);

  Future<void> _addBadge(String badgeId) async {
    if (!ProgressBadges.values.contains(badgeId) || hasBadge(badgeId)) return;
    _progress = _progress.copyWith(
      badges: List<String>.from(_progress.badges)..add(badgeId),
    );
    notifyListeners();
    await _persistProgress();
  }

  UserProgress _readLocalProgress({required String prefix}) {
    final storedCompleted = _storage.getStringList(
      '$prefix$_completedLessonsKey',
    );
    final completed = (_lessonIds.isEmpty
            ? storedCompleted
            : storedCompleted.where(_lessonIds.contains))
        .toSet()
        .toList(growable: false);
    var quizScores = _sanitizeQuizScores(
      _storage.getIntMap('$prefix$_quizBestScoresKey'),
    );
    if (prefix.isEmpty && quizScores.isEmpty) {
      quizScores = _migrateLegacyQuizScore(
        _storage.getInt(_legacyQuizScoreKey),
      );
    }
    final badges = _storage
        .getStringList('$prefix$_badgesKey')
        .map(ProgressBadges.normalize)
        .whereType<String>()
        .toSet()
        .toList();
    if (completed.isNotEmpty && !badges.contains(ProgressBadges.aiExplorer)) {
      badges.add(ProgressBadges.aiExplorer);
    }
    if (quizScores.values.any((score) => score > 0) &&
        !badges.contains(ProgressBadges.quizAce)) {
      badges.add(ProgressBadges.quizAce);
    }
    return UserProgress(
      completedLessonIds: completed,
      totalLessons: _lessonIds.length,
      quizBestScores: quizScores,
      badges: badges,
      knowledgeLevel: _storage.getString(
        '$prefix$_knowledgeLevelKey',
        defaultValue: 'Beginner',
      ),
    );
  }

  UserProgress _mergeProgress(UserProgress first, UserProgress second) {
    final lessons = {...first.completedLessonIds, ...second.completedLessonIds};
    final badges = {...first.badges, ...second.badges};
    final scores = <String, int>{...first.quizBestScores};
    for (final entry in second.quizBestScores.entries) {
      final previous = scores[entry.key] ?? 0;
      if (entry.value > previous) scores[entry.key] = entry.value;
    }
    return UserProgress(
      completedLessonIds: lessons.toList(growable: false),
      totalLessons: _lessonIds.length,
      quizBestScores: scores,
      badges: badges.toList(growable: false),
      knowledgeLevel: first.knowledgeLevel,
    );
  }

  UserProgress _sanitizeProgress(UserProgress value) {
    final completedLessons = _lessonIds.isEmpty
        ? value.completedLessonIds.toSet().toList(growable: false)
        : value.completedLessonIds
              .where(_lessonIds.contains)
              .toSet()
              .toList(growable: false);

    return UserProgress(
      completedLessonIds: completedLessons,
      totalLessons: _lessonIds.length,
      quizBestScores: _sanitizeQuizScores(value.quizBestScores),
      badges: value.badges
          .map(ProgressBadges.normalize)
          .whereType<String>()
          .toSet()
          .toList(growable: false),
      knowledgeLevel: value.knowledgeLevel,
    );
  }

  Map<String, int> _sanitizeQuizScores(Map<String, int> storedScores) {
    // Never delete historical quiz keys just because live content has not
    // loaded yet, was archived, or was temporarily absent from a cached list.
    // Current screens read scores by current quiz ID, while Phase 6 can still
    // reconcile valid historical evidence later.
    final result = <String, int>{};
    for (final entry in storedScores.entries) {
      final id = entry.key.trim();
      if (id.isEmpty || entry.value <= 0) continue;
      result[id] = entry.value.clamp(0, 100).toInt();
    }
    return result;
  }

  Map<String, int> _migrateLegacyQuizScore(int legacyScore) {
    if (legacyScore <= 0 || _quizIds.isEmpty) return const {};
    final count = (legacyScore ~/ 100).clamp(0, _quizIds.length).toInt();
    return {for (var index = 0; index < count; index++) _quizIds[index]: 100};
  }

  void _updateLevelInMemory() {
    var level = 'Beginner';
    if (_progress.completedLessons >= _progress.totalLessons &&
        currentQuizScore >= maximumQuizScore &&
        maximumQuizScore > 0) {
      level = 'Advanced';
    } else if (_progress.completedLessons >= 2 || currentQuizScore >= 100) {
      level = 'Intermediate';
    }
    if (level != _progress.knowledgeLevel) {
      _progress = _progress.copyWith(knowledgeLevel: level);
    }
  }

  Future<void> _persistProgress() async {
    final userId = _activeUserId;
    final prefix = userId == null ? '' : _prefixFor(userId);
    try {
      await _persistLocal(prefix: prefix);
      if (userId != null && _remoteRepository != null) {
        _syncState = ProgressSyncState.syncing;
        notifyListeners();
        await _remoteRepository.upsertProgress(
          userId: userId,
          progress: _progress,
        );
        if (_activeUserId != userId) return;
        _syncState = ProgressSyncState.synced;
        _lastSyncedAt = DateTime.now();
      }
    } catch (_) {
      _syncState = userId == null
          ? ProgressSyncState.localOnly
          : ProgressSyncState.error;
      _errorMessage = userId == null
          ? 'Your latest progress is visible, but it could not be saved on this device.'
          : 'Your progress is saved on this device. It will update online when the connection is available.';
    }
    notifyListeners();
  }

  Future<void> _persistLocal({
    required String prefix,
    bool clearLegacyScore = false,
  }) async {
    await _storage.setStringList(
      '$prefix$_completedLessonsKey',
      _progress.completedLessonIds,
    );
    await _storage.setIntMap(
      '$prefix$_quizBestScoresKey',
      _progress.quizBestScores,
    );
    await _storage.setStringList('$prefix$_badgesKey', _progress.badges);
    await _storage.setString(
      '$prefix$_knowledgeLevelKey',
      _progress.knowledgeLevel,
    );
    if (clearLegacyScore) await _storage.remove(_legacyQuizScoreKey);
  }

  String _prefixFor(String userId) => 'user:$userId:';
}
