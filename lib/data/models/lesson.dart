import './learning_topic.dart';

class Lesson {
  final String id;
  final String title;
  final String content;
  final int estimatedMinutes;
  final String quizId;
  final LearningTopic? topic;
  final int learningLevel;

  const Lesson({
    required this.id,
    required this.title,
    required this.content,
    required this.estimatedMinutes,
    required this.quizId,
    this.topic,
    this.learningLevel = 1,
  });
}

class Module {
  final String id;
  final String title;
  final String description;
  final List<Lesson> lessons;
  final String icon;
  final LearningTopic? topic;

  const Module({
    required this.id,
    required this.title,
    required this.description,
    required this.lessons,
    required this.icon,
    this.topic,
  });
}
