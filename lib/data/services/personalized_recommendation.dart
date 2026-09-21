import '../models/adaptive_learning.dart';
import '../models/learning_survey.dart';
import '../models/learning_topic.dart';

class PersonalizedRecommendation {
  final LearningTopic? topic;
  final String reason;
  const PersonalizedRecommendation(this.topic, this.reason);
}

/// A transparent, deterministic suggestion. Survey choices are preferences;
/// verified quiz/diagnostic attempts remain the only mastery evidence.
PersonalizedRecommendation choosePersonalizedRecommendation({
  required LearningSurvey? survey,
  required Map<LearningTopic, TopicMastery> mastery,
  required List<TopicMastery> dueReviews,
  required bool diagnosticCompleted,
  required LearningTopic? fallbackTopic,
  required String fallbackReason,
}) {
  if (!diagnosticCompleted) {
    return const PersonalizedRecommendation(null,
        'Complete the starting check to find out where to begin.');
  }
  if (dueReviews.isNotEmpty) {
    final topic = dueReviews.first.topic;
    return PersonalizedRecommendation(topic,
        '${topic.label} is due for review based on your practice history.');
  }
  if (survey == null || survey.interests.isEmpty) {
    return PersonalizedRecommendation(fallbackTopic, fallbackReason);
  }

  final interests = survey.interests.toList();
  final goalTopic = switch (survey.learningGoal) {
    'write_better_prompts' => LearningTopic.promptClarity,
    'verify_information' => LearningTopic.verification,
    'use_ai_responsibly' => LearningTopic.responsibleUse,
    _ => null,
  };
  interests.sort((a, b) {
    final aMastery = mastery[a] ?? TopicMastery.initial(a);
    final bMastery = mastery[b] ?? TopicMastery.initial(b);
    // Beginners encounter unfamiliar selected interests first; experienced
    // learners prioritize observed gaps and then topics not attempted yet.
    if (survey.experienceLevel == 'beginner' &&
        (aMastery.attempts == 0) != (bMastery.attempts == 0)) {
      return aMastery.attempts == 0 ? -1 : 1;
    }
    if (aMastery.attempts > 0 && bMastery.attempts > 0) {
      final byMastery = aMastery.mastery.compareTo(bMastery.mastery);
      if (byMastery != 0) return byMastery;
    }
    if ((a == goalTopic) != (b == goalTopic)) return a == goalTopic ? -1 : 1;
    return a.index.compareTo(b.index);
  });

  final topic = interests.first;
  final current = mastery[topic] ?? TopicMastery.initial(topic);
  if (current.attempts == 0) {
    return PersonalizedRecommendation(topic,
        '${topic.label} matches your selected interests and has not been practiced yet.');
  }
  // Do not keep recommending a mastered interest when there are documented
  // gaps elsewhere in the learner's diagnostic/practice history.
  if (current.mastery >= 80 && fallbackTopic != null &&
      (mastery[fallbackTopic]?.mastery ?? 0) < current.mastery) {
    return PersonalizedRecommendation(fallbackTopic, fallbackReason);
  }
  return PersonalizedRecommendation(topic,
      '${topic.label} matches your interests and is at ${current.mastery}% mastery.');
}
