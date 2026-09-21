import './learning_topic.dart';

/// Learner-provided preferences. These are not a measurement of ability.
class LearningSurvey {
  final Set<LearningTopic> interests;
  final String experienceLevel;
  final String learningGoal;
  final DateTime? updatedAt;

  const LearningSurvey({
    required this.interests,
    required this.experienceLevel,
    required this.learningGoal,
    this.updatedAt,
  });

  static const experienceLevels = <String, String>{
    'beginner': 'New to AI',
    'some_experience': 'I have tried AI tools',
    'experienced': 'I use AI regularly',
  };

  static const learningGoals = <String, String>{
    'write_better_prompts': 'Write clearer prompts',
    'verify_information': 'Check AI-generated information',
    'use_ai_responsibly': 'Use AI safely and responsibly',
    'explore_ai': 'Explore AI literacy',
  };

  factory LearningSurvey.fromMap(Map<String, dynamic> data) {
    final raw = data['interests'];
    final topics = raw is List
        ? raw.map((value) => LearningTopicX.fromId(value.toString()))
            .whereType<LearningTopic>().toSet()
        : <LearningTopic>{};
    final experience = data['experience_level']?.toString() ?? '';
    final goal = data['learning_goal']?.toString() ?? '';
    if (topics.isEmpty || topics.length > 3 ||
        !experienceLevels.containsKey(experience) ||
        !learningGoals.containsKey(goal)) {
      throw const FormatException('Invalid learning survey data.');
    }
    return LearningSurvey(
      interests: topics,
      experienceLevel: experience,
      learningGoal: goal,
      updatedAt: DateTime.tryParse(data['updated_at']?.toString() ?? ''),
    );
  }

  void validate() {
    if (interests.isEmpty || interests.length > 3 ||
        !experienceLevels.containsKey(experienceLevel) ||
        !learningGoals.containsKey(learningGoal)) {
      throw ArgumentError('Choose 1–3 interests, an experience level and a goal.');
    }
  }
}
