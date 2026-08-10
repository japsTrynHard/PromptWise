class Lesson {
  final String id;
  final String title;
  final String content;
  final int estimatedMinutes;
  final String quizId;

  const Lesson({
    required this.id,
    required this.title,
    required this.content,
    required this.estimatedMinutes,
    required this.quizId,
  });
}

class Module {
  final String id;
  final String title;
  final String description;
  final List<Lesson> lessons;
  final String icon;

  const Module({
    required this.id,
    required this.title,
    required this.description,
    required this.lessons,
    required this.icon,
  });
}
