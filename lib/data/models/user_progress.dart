class UserProgress {
  final List<String> completedLessonIds;
  final int totalLessons;
  final Map<String, int> quizBestScores;
  final List<String> badges;
  final String knowledgeLevel;

  const UserProgress({
    required this.completedLessonIds,
    required this.totalLessons,
    required this.quizBestScores,
    required this.badges,
    required this.knowledgeLevel,
  });

  int get completedLessons => completedLessonIds.length;

  int get quizScore =>
      quizBestScores.values.fold<int>(0, (total, score) => total + score);

  double get completionRatio {
    if (totalLessons == 0) return 0;
    return (completedLessons / totalLessons).clamp(0, 1).toDouble();
  }

  factory UserProgress.initial({required int totalLessons}) => UserProgress(
    completedLessonIds: const [],
    totalLessons: totalLessons,
    quizBestScores: const {},
    badges: const [],
    knowledgeLevel: 'Beginner',
  );

  UserProgress copyWith({
    List<String>? completedLessonIds,
    int? totalLessons,
    Map<String, int>? quizBestScores,
    List<String>? badges,
    String? knowledgeLevel,
  }) {
    return UserProgress(
      completedLessonIds: completedLessonIds ?? this.completedLessonIds,
      totalLessons: totalLessons ?? this.totalLessons,
      quizBestScores: quizBestScores ?? this.quizBestScores,
      badges: badges ?? this.badges,
      knowledgeLevel: knowledgeLevel ?? this.knowledgeLevel,
    );
  }
}
