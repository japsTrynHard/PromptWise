import 'learning_topic.dart';

class TopicMastery {
  final LearningTopic topic;
  final int mastery;
  final int attempts;
  final int correctAnswers;
  final DateTime? lastPracticedAt;
  final DateTime? nextReviewAt;

  const TopicMastery({
    required this.topic,
    required this.mastery,
    required this.attempts,
    required this.correctAnswers,
    this.lastPracticedAt,
    this.nextReviewAt,
  });

  factory TopicMastery.initial(LearningTopic topic) => TopicMastery(
    topic: topic,
    mastery: 0,
    attempts: 0,
    correctAnswers: 0,
  );

  factory TopicMastery.fromMap(Map<String, dynamic> map) {
    final topic = LearningTopicX.fromId(map['topic_id']?.toString());
    return TopicMastery(
      topic: topic ?? LearningTopic.promptClarity,
      mastery: _asInt(map['mastery']).clamp(0, 100).toInt(),
      attempts: _asInt(map['attempts']),
      correctAnswers: _asInt(map['correct_answers']),
      lastPracticedAt: _asDate(map['last_practiced_at']),
      nextReviewAt: _asDate(map['next_review_at']),
    );
  }

  Map<String, dynamic> toMap({String? userId}) => {
    if (userId != null) 'user_id': userId,
    'topic_id': topic.id,
    'mastery': mastery,
    'attempts': attempts,
    'correct_answers': correctAnswers,
    'last_practiced_at': lastPracticedAt?.toUtc().toIso8601String(),
    'next_review_at': nextReviewAt?.toUtc().toIso8601String(),
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  TopicMastery copyWith({
    int? mastery,
    int? attempts,
    int? correctAnswers,
    DateTime? lastPracticedAt,
    DateTime? nextReviewAt,
  }) {
    return TopicMastery(
      topic: topic,
      mastery: mastery ?? this.mastery,
      attempts: attempts ?? this.attempts,
      correctAnswers: correctAnswers ?? this.correctAnswers,
      lastPracticedAt: lastPracticedAt ?? this.lastPracticedAt,
      nextReviewAt: nextReviewAt ?? this.nextReviewAt,
    );
  }

  bool get isDueForReview {
    final due = nextReviewAt;
    return due != null && !due.isAfter(DateTime.now());
  }
}

class DiagnosticQuestion {
  final String id;
  final LearningTopic topic;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const DiagnosticQuestion({
    required this.id,
    required this.topic,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });
}

class DiagnosticResult {
  final int score;
  final int correctAnswers;
  final int totalQuestions;
  final Map<LearningTopic, bool> topicResults;

  const DiagnosticResult({
    required this.score,
    required this.correctAnswers,
    required this.totalQuestions,
    required this.topicResults,
  });
}

const diagnosticQuestions = <DiagnosticQuestion>[
  DiagnosticQuestion(
    id: 'diagnostic_prompt_clarity',
    topic: LearningTopic.promptClarity,
    question: 'Which prompt gives the clearest task to an AI assistant?',
    options: [
      'Help me with school.',
      'Explain photosynthesis in simple language for a Grade 8 student.',
      'Tell me something useful.',
      'Write anything about science.',
    ],
    correctIndex: 1,
    explanation:
        'A clear prompt states the exact task and what the response should focus on.',
  ),
  DiagnosticQuestion(
    id: 'diagnostic_context',
    topic: LearningTopic.context,
    question: 'Why is context useful when writing a prompt?',
    options: [
      'It makes every answer longer.',
      'It tells the AI relevant background, purpose, or audience.',
      'It guarantees that every AI answer is true.',
      'It removes the need to review the response.',
    ],
    correctIndex: 1,
    explanation:
        'Context helps the response fit the learner’s situation, purpose, and audience.',
  ),
  DiagnosticQuestion(
    id: 'diagnostic_specificity',
    topic: LearningTopic.specificity,
    question: 'Which addition makes a prompt more specific?',
    options: [
      'Adding an expected format and useful constraints.',
      'Removing the topic.',
      'Using fewer meaningful details.',
      'Asking several unrelated tasks at once.',
    ],
    correctIndex: 0,
    explanation:
        'Useful constraints and an expected output format make the request more precise.',
  ),
  DiagnosticQuestion(
    id: 'diagnostic_responsible_use',
    topic: LearningTopic.responsibleUse,
    question: 'What is the safest choice before sharing information with an AI tool?',
    options: [
      'Include private passwords so the AI has more context.',
      'Share every personal detail available.',
      'Remove unnecessary private or sensitive information.',
      'Assume all AI tools keep every message private forever.',
    ],
    correctIndex: 2,
    explanation:
        'Only information necessary for the task should be shared, especially when personal or sensitive data is involved.',
  ),
  DiagnosticQuestion(
    id: 'diagnostic_verification',
    topic: LearningTopic.verification,
    question: 'What should you do before trusting an important factual claim from AI?',
    options: [
      'Trust it because the answer sounds confident.',
      'Check reliable sources and supporting evidence.',
      'Share it immediately.',
      'Assume the first answer is always complete.',
    ],
    correctIndex: 1,
    explanation:
        'Important claims should be checked against reliable sources and evidence before they are accepted or shared.',
  ),
];

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _asDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}



String philippinesDayKey(DateTime value) {
  // PromptWise currently serves Philippine learners. Using one canonical
  // learning-day boundary avoids UTC rolling the anti-farming day at 8:00 AM.
  final ph = value.toUtc().add(const Duration(hours: 8));
  return '${ph.year.toString().padLeft(4, '0')}-'
      '${ph.month.toString().padLeft(2, '0')}-'
      '${ph.day.toString().padLeft(2, '0')}';
}

class AdaptiveQuestionAttemptRecord {
  final String itemId;
  final LearningTopic topic;
  final bool isCorrect;
  final String attemptType;
  final bool countedForMastery;
  final DateTime attemptedAt;

  const AdaptiveQuestionAttemptRecord({
    required this.itemId,
    required this.topic,
    required this.isCorrect,
    required this.attemptType,
    required this.countedForMastery,
    required this.attemptedAt,
  });

  factory AdaptiveQuestionAttemptRecord.fromMap(Map<String, dynamic> map) {
    final topic = LearningTopicX.fromId(map['topic_id']?.toString());
    if (topic == null) {
      throw const FormatException('Unknown adaptive learning topic.');
    }
    return AdaptiveQuestionAttemptRecord(
      itemId: map['item_id']?.toString() ?? '',
      topic: topic,
      isCorrect: map['is_correct'] == true,
      attemptType: map['attempt_type']?.toString() ?? 'quiz',
      countedForMastery: map['counted_for_mastery'] == true,
      attemptedAt: _asDate(map['attempted_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  String get masteryKey {
    final base = '$attemptType::$itemId::${topic.id}';
    if (attemptType == 'legacy_quiz') return base;
    return '$base::${philippinesDayKey(attemptedAt)}';
  }

  String get itemTopicKey => '$itemId::${topic.id}';
}

class DiagnosticAttemptRecord {
  final Map<String, int> answers;
  final DateTime completedAt;

  const DiagnosticAttemptRecord({
    required this.answers,
    required this.completedAt,
  });

  factory DiagnosticAttemptRecord.fromMap(Map<String, dynamic> map) {
    final answers = <String, int>{};
    final raw = map['answers'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final value = entry.value;
        if (value is int) {
          answers[entry.key.toString()] = value;
        } else if (value is num) {
          answers[entry.key.toString()] = value.toInt();
        } else {
          final parsed = int.tryParse(value?.toString() ?? '');
          if (parsed != null) answers[entry.key.toString()] = parsed;
        }
      }
    }
    return DiagnosticAttemptRecord(
      answers: answers,
      completedAt: _asDate(map['completed_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
