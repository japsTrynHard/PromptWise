import 'package:flutter/foundation.dart';

import '../models/user_progress.dart';
import '../services/storage_service.dart';

class ProgressController extends ChangeNotifier {
  ProgressController({required int totalLessons})
      : _progress = UserProgress.initial(totalLessons: totalLessons);

  static const _completedLessonsKey = 'completedLessonIds';
  static const _quizScoreKey = 'quizScore';
  static const _badgesKey = 'badges';
  static const _knowledgeLevelKey = 'knowledgeLevel';

  final StorageService _storage = StorageService();
  UserProgress _progress;

  UserProgress get progress => _progress;

  Future<void> init() async {
    await _storage.init();
    _progress = UserProgress(
      completedLessonIds: _storage.getStringList(_completedLessonsKey),
      totalLessons: _progress.totalLessons,
      quizScore: _storage.getInt(_quizScoreKey),
      badges: _storage.getStringList(_badgesKey),
      knowledgeLevel: _storage.getString(
        _knowledgeLevelKey,
        defaultValue: 'Beginner',
      ),
    );
    notifyListeners();
  }

  bool isLessonCompleted(String lessonId) {
    return _progress.completedLessonIds.contains(lessonId);
  }

  Future<void> completeLesson(String lessonId) async {
    if (isLessonCompleted(lessonId)) return;

    final completed = List<String>.from(_progress.completedLessonIds)
      ..add(lessonId);

    _progress = _progress.copyWith(completedLessonIds: completed);
    await _storage.setStringList(_completedLessonsKey, completed);

    if (completed.length == 1) {
      await addBadge('🏆 AI Explorer');
    }

    await _updateLevel();
    notifyListeners();
  }

  Future<void> addQuizScore(int points) async {
    if (points <= 0) return;

    _progress = _progress.copyWith(quizScore: _progress.quizScore + points);
    await _storage.setInt(_quizScoreKey, _progress.quizScore);
    await addBadge('⚡ Quiz Ace');
    await _updateLevel();
    notifyListeners();
  }

  Future<void> addBadge(String badge) async {
    if (_progress.badges.contains(badge)) return;

    final updatedBadges = List<String>.from(_progress.badges)..add(badge);
    _progress = _progress.copyWith(badges: updatedBadges);
    await _storage.setStringList(_badgesKey, updatedBadges);
    notifyListeners();
  }

  Future<void> addGameBadge() => addBadge('🕵️ AI Detective');

  Future<void> addSandboxBadge() => addBadge('✍️ Prompt Improver');

  Future<void> _updateLevel() async {
    String level = 'Beginner';

    if (_progress.completedLessons >= _progress.totalLessons &&
        _progress.quizScore >= 300) {
      level = 'Advanced';
    } else if (_progress.completedLessons >= 2) {
      level = 'Intermediate';
    }

    if (level == _progress.knowledgeLevel) return;

    _progress = _progress.copyWith(knowledgeLevel: level);
    await _storage.setString(_knowledgeLevelKey, level);
  }
}
