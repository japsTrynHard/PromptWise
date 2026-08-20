import 'learning_topic.dart';

class Quiz {
  final String id;
  final String title;
  final String description;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final LearningTopic? topic;

  const Quiz({
    required this.id,
    this.title = '',
    this.description = '',
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    this.topic,
  });

  bool get isValid =>
      id.trim().isNotEmpty &&
      question.trim().isNotEmpty &&
      options.length >= 2 &&
      correctIndex >= 0 &&
      correctIndex < options.length;

  String get displayTitle => title.trim().isEmpty ? 'Knowledge check' : title;
}
