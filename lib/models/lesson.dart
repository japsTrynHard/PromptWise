class Lesson {
  final String id;
  final String title;
  final String content;
  final int estimatedMinutes;

  const Lesson({
    required this.id,
    required this.title,
    required this.content,
    required this.estimatedMinutes,
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
