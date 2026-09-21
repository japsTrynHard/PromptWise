import 'package:flutter_test/flutter_test.dart';
import 'package:promptwise/data/models/adaptive_learning.dart';
import 'package:promptwise/data/models/learning_survey.dart';
import 'package:promptwise/data/models/learning_topic.dart';
import 'package:promptwise/data/services/personalized_recommendation.dart';

PersonalizedRecommendation decide({
  LearningSurvey? survey,
  Map<LearningTopic, TopicMastery> mastery = const {},
  List<TopicMastery> due = const [],
  bool diagnosticCompleted = true,
}) => choosePersonalizedRecommendation(
  survey: survey,
  mastery: mastery,
  dueReviews: due,
  diagnosticCompleted: diagnosticCompleted,
  fallbackTopic: LearningTopic.context,
  fallbackReason: 'Review context based on prior quiz results.',
);

const _survey = LearningSurvey(
  interests: {LearningTopic.verification},
  experienceLevel: 'beginner',
  learningGoal: 'verify_information',
);

void main() {
  test('starting check remains prerequisite, not replaced by survey', () {
    final decision = decide(survey: _survey, diagnosticCompleted: false);
    expect(decision.topic, isNull);
    expect(decision.reason, contains('starting check'));
  });

  test('due spaced review outranks survey interest', () {
    final due = TopicMastery(
      topic: LearningTopic.context,
      mastery: 35,
      attempts: 2,
      correctAnswers: 1,
      nextReviewAt: DateTime.utc(2025),
    );
    final decision = decide(survey: _survey, due: [due]);
    expect(decision.topic, LearningTopic.context);
    expect(decision.reason, contains('due for review'));
  });

  test('new learner starts with their selected interest', () {
    final decision = decide(survey: _survey);
    expect(decision.topic, LearningTopic.verification);
    expect(decision.reason, contains('selected interests'));
  });

  test('a mastered interest yields to a documented weaker area', () {
    final decision = decide(survey: _survey, mastery: {
      LearningTopic.verification: const TopicMastery(
        topic: LearningTopic.verification,
        mastery: 90,
        attempts: 8,
        correctAnswers: 7,
      ),
      LearningTopic.context: const TopicMastery(
        topic: LearningTopic.context,
        mastery: 40,
        attempts: 3,
        correctAnswers: 1,
      ),
    });
    expect(decision.topic, LearningTopic.context);
  });

  test('existing accounts without survey retain original recommendation', () {
    final decision = decide();
    expect(decision.topic, LearningTopic.context);
    expect(decision.reason, contains('prior quiz results'));
  });

  test('invalid survey payload is rejected by the model', () {
    expect(
      () => LearningSurvey.fromMap({
        'interests': ['not_real'],
        'experience_level': 'beginner',
        'learning_goal': 'explore_ai',
      }),
      throwsFormatException,
    );
  });
}
