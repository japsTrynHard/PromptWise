class UserProgress {
  final List<String> completedLessonIds;
  final int totalLessons;
  final int quizScore;
  final List<String> badges;
  final String knowledgeLevel;

  const UserProgress({
    required this.completedLessonIds,
    required this.totalLessons,
    required this.quizScore,
    required this.badges,
    required this.knowledgeLevel,
  });

  int get completedLessons => completedLessonIds.length;

  double get completionRatio {
    if (totalLessons == 0) return 0;
    return (completedLessons / totalLessons).clamp(0, 1);
  }

  factory UserProgress.initial({required int totalLessons}) => UserProgress(
        completedLessonIds: const [],
        totalLessons: totalLessons,
        quizScore: 0,
        badges: const [],
        knowledgeLevel: 'Beginner',
      );

  UserProgress copyWith({
    List<String>? completedLessonIds,
    int? totalLessons,
    int? quizScore,
    List<String>? badges,
    String? knowledgeLevel,
  }) {
    return UserProgress(
      completedLessonIds: completedLessonIds ?? this.completedLessonIds,
      totalLessons: totalLessons ?? this.totalLessons,
      quizScore: quizScore ?? this.quizScore,
      badges: badges ?? this.badges,
      knowledgeLevel: knowledgeLevel ?? this.knowledgeLevel,
    );
  }
}
