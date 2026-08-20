import 'learning_topic.dart';

enum LearningRank {
  foundation,
  developing,
  proficient,
  advanced,
  expert,
}

extension LearningRankX on LearningRank {
  int get level => index + 1;

  String get label => switch (this) {
    LearningRank.foundation => 'Foundation',
    LearningRank.developing => 'Developing',
    LearningRank.proficient => 'Proficient',
    LearningRank.advanced => 'Advanced',
    LearningRank.expert => 'Expert',
  };

  static LearningRank fromLevel(int level) {
    final safe = level.clamp(1, 5);
    return LearningRank.values[safe - 1];
  }
}

enum QuestionDifficulty {
  foundation,
  developing,
  proficient,
  advanced,
  expert,
}

extension QuestionDifficultyX on QuestionDifficulty {
  int get level => index + 1;

  String get label => switch (this) {
    QuestionDifficulty.foundation => 'Foundation',
    QuestionDifficulty.developing => 'Developing',
    QuestionDifficulty.proficient => 'Proficient',
    QuestionDifficulty.advanced => 'Advanced',
    QuestionDifficulty.expert => 'Expert',
  };

  static QuestionDifficulty fromLevel(int level) {
    final safe = level.clamp(1, 5);
    return QuestionDifficulty.values[safe - 1];
  }
}

enum KnowledgeQuestionType {
  concept,
  scenario,
  bestResponse,
  evaluation,
}

extension KnowledgeQuestionTypeX on KnowledgeQuestionType {
  String get databaseValue => switch (this) {
    KnowledgeQuestionType.concept => 'concept',
    KnowledgeQuestionType.scenario => 'scenario',
    KnowledgeQuestionType.bestResponse => 'best_response',
    KnowledgeQuestionType.evaluation => 'evaluation',
  };

  String get label => switch (this) {
    KnowledgeQuestionType.concept => 'Concept',
    KnowledgeQuestionType.scenario => 'Scenario',
    KnowledgeQuestionType.bestResponse => 'Best response',
    KnowledgeQuestionType.evaluation => 'Evaluation',
  };

  static KnowledgeQuestionType fromDatabase(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'scenario' => KnowledgeQuestionType.scenario,
      'best_response' => KnowledgeQuestionType.bestResponse,
      'evaluation' => KnowledgeQuestionType.evaluation,
      _ => KnowledgeQuestionType.concept,
    };
  }
}

class LearningObjective {
  final String id;
  final String contentItemId;
  final LearningTopic topic;
  final String code;
  final String title;
  final String description;
  final int requiredLevel;
  final int sortOrder;

  const LearningObjective({
    required this.id,
    required this.contentItemId,
    required this.topic,
    required this.code,
    required this.title,
    required this.description,
    required this.requiredLevel,
    required this.sortOrder,
  });

  factory LearningObjective.fromMap(Map<String, dynamic> map) {
    final topic = LearningTopicX.fromId(map['topic_id']?.toString());
    if (topic == null) {
      throw const FormatException('Learning objective has an unknown topic.');
    }
    return LearningObjective(
      id: map['id']?.toString() ?? '',
      contentItemId: map['content_item_id']?.toString() ?? '',
      topic: topic,
      code: map['objective_code']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      requiredLevel: _asInt(map['required_level'], fallback: 1).clamp(1, 5),
      sortOrder: _asInt(map['sort_order']),
    );
  }
}

class LearnerTopicRank {
  final LearningTopic topic;
  final LearningRank rank;
  final int tier;
  final int progress;
  final int highestDifficultyPassed;
  final int objectiveCoverage;
  final int retentionPasses;
  final DateTime? updatedAt;

  const LearnerTopicRank({
    required this.topic,
    required this.rank,
    required this.tier,
    required this.progress,
    required this.highestDifficultyPassed,
    required this.objectiveCoverage,
    required this.retentionPasses,
    this.updatedAt,
  });

  factory LearnerTopicRank.initial(LearningTopic topic) => LearnerTopicRank(
    topic: topic,
    rank: LearningRank.foundation,
    tier: 1,
    progress: 0,
    highestDifficultyPassed: 0,
    objectiveCoverage: 0,
    retentionPasses: 0,
  );

  factory LearnerTopicRank.fromMap(Map<String, dynamic> map) {
    final topic = LearningTopicX.fromId(map['topic_id']?.toString());
    if (topic == null) {
      throw const FormatException('Learner rank has an unknown topic.');
    }
    return LearnerTopicRank(
      topic: topic,
      rank: LearningRankX.fromLevel(_asInt(map['rank_level'], fallback: 1)),
      tier: _asInt(map['rank_tier'], fallback: 1).clamp(1, 3),
      progress: _asInt(map['rank_progress']).clamp(0, 100),
      highestDifficultyPassed: _asInt(
        map['highest_difficulty_passed'],
      ).clamp(0, 5),
      objectiveCoverage: _asInt(map['objective_coverage']).clamp(0, 100),
      retentionPasses: _asInt(map['retention_passes']).clamp(0, 999),
      updatedAt: _asDate(map['updated_at']),
    );
  }

  String get displayLabel => '${rank.label} ${_romanTier(tier)}';
}

class KnowledgeCheckQuestion {
  final String id;
  final LearningTopic topic;
  final String? objectiveId;
  final String objectiveTitle;
  final String stem;
  final List<String> options;
  final QuestionDifficulty difficulty;
  final KnowledgeQuestionType type;
  final int sequence;

  const KnowledgeCheckQuestion({
    required this.id,
    required this.topic,
    required this.objectiveId,
    required this.objectiveTitle,
    required this.stem,
    required this.options,
    required this.difficulty,
    required this.type,
    required this.sequence,
  });

  factory KnowledgeCheckQuestion.fromMap(Map<String, dynamic> map) {
    final topic = LearningTopicX.fromId(map['topic_id']?.toString());
    if (topic == null) {
      throw const FormatException('Knowledge-check question has an unknown topic.');
    }
    final rawOptions = map['options'];
    final options = rawOptions is List
        ? rawOptions.map((item) => item.toString()).toList(growable: false)
        : const <String>[];
    return KnowledgeCheckQuestion(
      id: map['question_id']?.toString() ?? map['id']?.toString() ?? '',
      topic: topic,
      objectiveId: _nullableString(map['objective_id']),
      objectiveTitle: map['objective_title']?.toString() ?? '',
      stem: map['stem']?.toString() ?? '',
      options: options,
      difficulty: QuestionDifficultyX.fromLevel(
        _asInt(map['difficulty'], fallback: 1),
      ),
      type: KnowledgeQuestionTypeX.fromDatabase(map['question_type']?.toString()),
      sequence: _asInt(map['sequence'], fallback: 1),
    );
  }

  bool get isValid =>
      id.isNotEmpty && stem.trim().isNotEmpty && options.length >= 2;
}

class KnowledgeCheckSession {
  final String id;
  final String mode;
  final LearningTopic? focusTopic;
  final List<KnowledgeCheckQuestion> questions;
  final DateTime startedAt;

  const KnowledgeCheckSession({
    required this.id,
    required this.mode,
    required this.focusTopic,
    required this.questions,
    required this.startedAt,
  });

  factory KnowledgeCheckSession.fromMap(Map<String, dynamic> map) {
    final rawQuestions = map['questions'];
    final questions = <KnowledgeCheckQuestion>[];
    if (rawQuestions is List) {
      for (final item in rawQuestions) {
        if (item is! Map) continue;
        try {
          final question = KnowledgeCheckQuestion.fromMap(
            Map<String, dynamic>.from(item),
          );
          if (question.isValid) questions.add(question);
        } on FormatException {
          // Ignore malformed server rows instead of breaking the whole session.
        }
      }
    }
    questions.sort((a, b) => a.sequence.compareTo(b.sequence));
    return KnowledgeCheckSession(
      id: map['session_id']?.toString() ?? map['id']?.toString() ?? '',
      mode: map['mode']?.toString() ?? 'adaptive',
      focusTopic: LearningTopicX.fromId(map['focus_topic']?.toString()),
      questions: List.unmodifiable(questions),
      startedAt: _asDate(map['started_at']) ?? DateTime.now(),
    );
  }
}

class KnowledgeAnswerFeedback {
  final String questionId;
  final bool isCorrect;
  final bool countedForMastery;
  final int correctIndex;
  final String explanation;
  final int? masteryAfter;

  const KnowledgeAnswerFeedback({
    required this.questionId,
    required this.isCorrect,
    required this.countedForMastery,
    required this.correctIndex,
    required this.explanation,
    this.masteryAfter,
  });

  factory KnowledgeAnswerFeedback.fromMap(Map<String, dynamic> map) {
    return KnowledgeAnswerFeedback(
      questionId: map['question_id']?.toString() ?? '',
      isCorrect: map['is_correct'] == true,
      countedForMastery: map['counted_for_mastery'] == true,
      correctIndex: _asInt(map['correct_index']),
      explanation: map['explanation']?.toString() ?? '',
      masteryAfter: map['mastery_after'] == null
          ? null
          : _asInt(map['mastery_after']).clamp(0, 100),
    );
  }
}

class KnowledgeCheckTopicResult {
  final LearningTopic topic;
  final int correct;
  final int total;

  const KnowledgeCheckTopicResult({
    required this.topic,
    required this.correct,
    required this.total,
  });

  double get ratio => total == 0 ? 0 : correct / total;
}

class KnowledgeCheckSummary {
  final String sessionId;
  final int correct;
  final int total;
  final List<KnowledgeCheckTopicResult> topics;
  final Map<LearningTopic, LearnerTopicRank> ranks;

  const KnowledgeCheckSummary({
    required this.sessionId,
    required this.correct,
    required this.total,
    required this.topics,
    required this.ranks,
  });

  factory KnowledgeCheckSummary.fromMap(Map<String, dynamic> map) {
    final topicResults = <KnowledgeCheckTopicResult>[];
    final rawTopics = map['topics'];
    if (rawTopics is List) {
      for (final item in rawTopics) {
        if (item is! Map) continue;
        final row = Map<String, dynamic>.from(item);
        final topic = LearningTopicX.fromId(row['topic_id']?.toString());
        if (topic == null) continue;
        topicResults.add(
          KnowledgeCheckTopicResult(
            topic: topic,
            correct: _asInt(row['correct']),
            total: _asInt(row['total']),
          ),
        );
      }
    }

    final rankMap = <LearningTopic, LearnerTopicRank>{};
    final rawRanks = map['ranks'];
    if (rawRanks is List) {
      for (final item in rawRanks) {
        if (item is! Map) continue;
        try {
          final rank = LearnerTopicRank.fromMap(
            Map<String, dynamic>.from(item),
          );
          rankMap[rank.topic] = rank;
        } on FormatException {
          // Ignore malformed rank rows.
        }
      }
    }

    return KnowledgeCheckSummary(
      sessionId: map['session_id']?.toString() ?? '',
      correct: _asInt(map['correct']),
      total: _asInt(map['total']),
      topics: List.unmodifiable(topicResults),
      ranks: Map.unmodifiable(rankMap),
    );
  }
}

String _romanTier(int tier) => switch (tier.clamp(1, 3)) {
  1 => 'I',
  2 => 'II',
  _ => 'III',
};

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

DateTime? _asDate(dynamic value) {
  if (value is DateTime) return value;
  final text = value?.toString();
  if (text == null || text.trim().isEmpty) return null;
  return DateTime.tryParse(text);
}

String? _nullableString(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
