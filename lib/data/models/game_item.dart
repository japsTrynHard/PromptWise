import './learning_topic.dart';

class GameRound {
  final String id;
  final String title;
  final String imagePathA;
  final String imagePathB;
  final bool isAAI;
  final String explanation;
  final LearningTopic topic;

  const GameRound({
    required this.id,
    this.title = 'Real or AI?',
    required this.imagePathA,
    required this.imagePathB,
    required this.isAAI,
    required this.explanation,
    this.topic = LearningTopic.verification,
  });
}
