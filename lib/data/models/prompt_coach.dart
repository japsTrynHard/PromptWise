import './learning_topic.dart';

enum PromptCoachMode { standard, ai }

extension PromptCoachModeX on PromptCoachMode {
  String get databaseValue => switch (this) {
    PromptCoachMode.standard => 'standard',
    PromptCoachMode.ai => 'ai',
  };

  String get label => switch (this) {
    PromptCoachMode.standard => 'Standard Coach',
    PromptCoachMode.ai => 'AI Coach',
  };

  static PromptCoachMode fromDatabase(String? value) {
    return value?.trim().toLowerCase() == 'ai'
        ? PromptCoachMode.ai
        : PromptCoachMode.standard;
  }
}

enum PromptRubricDimension {
  clarity,
  context,
  specificity,
  instructions,
  expectedOutput,
  constraints,
  privacySafety,
  responsibleUse,
}

extension PromptRubricDimensionX on PromptRubricDimension {
  String get key => switch (this) {
    PromptRubricDimension.clarity => 'clarity',
    PromptRubricDimension.context => 'context',
    PromptRubricDimension.specificity => 'specificity',
    PromptRubricDimension.instructions => 'instructions',
    PromptRubricDimension.expectedOutput => 'expected_output',
    PromptRubricDimension.constraints => 'constraints',
    PromptRubricDimension.privacySafety => 'privacy_safety',
    PromptRubricDimension.responsibleUse => 'responsible_use',
  };

  String get label => switch (this) {
    PromptRubricDimension.clarity => 'Clarity',
    PromptRubricDimension.context => 'Context',
    PromptRubricDimension.specificity => 'Specificity',
    PromptRubricDimension.instructions => 'Instructions',
    PromptRubricDimension.expectedOutput => 'Expected output',
    PromptRubricDimension.constraints => 'Constraints',
    PromptRubricDimension.privacySafety => 'Privacy & safety',
    PromptRubricDimension.responsibleUse => 'Responsible use',
  };

  LearningTopic get topic => switch (this) {
    PromptRubricDimension.clarity => LearningTopic.promptClarity,
    PromptRubricDimension.context => LearningTopic.context,
    PromptRubricDimension.specificity => LearningTopic.specificity,
    PromptRubricDimension.instructions => LearningTopic.specificity,
    PromptRubricDimension.expectedOutput => LearningTopic.specificity,
    PromptRubricDimension.constraints => LearningTopic.specificity,
    PromptRubricDimension.privacySafety => LearningTopic.responsibleUse,
    PromptRubricDimension.responsibleUse => LearningTopic.responsibleUse,
  };
}

class PromptRubricScore {
  final Map<PromptRubricDimension, double> values;

  PromptRubricScore(Map<PromptRubricDimension, double> values)
    : values = Map.unmodifiable({
        for (final dimension in PromptRubricDimension.values)
          dimension: (values[dimension] ?? 0).clamp(0.0, 1.0).toDouble(),
      });

  factory PromptRubricScore.zero() => PromptRubricScore(const {});

  factory PromptRubricScore.fromMap(Map<String, dynamic> map) {
    double read(PromptRubricDimension dimension) {
      final raw = map[dimension.key];
      if (raw is num) return raw.toDouble().clamp(0.0, 1.0).toDouble();
      return (double.tryParse(raw?.toString() ?? '') ?? 0)
          .clamp(0.0, 1.0)
          .toDouble();
    }

    return PromptRubricScore({
      for (final dimension in PromptRubricDimension.values)
        dimension: read(dimension),
    });
  }

  double valueFor(PromptRubricDimension dimension) => values[dimension] ?? 0;

  double get overall {
    if (values.isEmpty) return 0;
    final total = PromptRubricDimension.values.fold<double>(
      0,
      (sum, dimension) => sum + valueFor(dimension),
    );
    return total / PromptRubricDimension.values.length;
  }

  int get overallPercent => (overall * 100).round().clamp(0, 100);

  double topicScore(LearningTopic topic) {
    final dimensions = PromptRubricDimension.values
        .where((dimension) => dimension.topic == topic)
        .toList(growable: false);
    if (dimensions.isEmpty) return 0;
    final total = dimensions.fold<double>(
      0,
      (sum, dimension) => sum + valueFor(dimension),
    );
    return total / dimensions.length;
  }

  Map<String, dynamic> toMap() => {
    for (final dimension in PromptRubricDimension.values)
      dimension.key: valueFor(dimension),
    'overall': overall,
  };
}

class PromptPrivacyFinding {
  final String code;
  final String label;
  final String message;
  final bool blocksAi;

  const PromptPrivacyFinding({
    required this.code,
    required this.label,
    required this.message,
    required this.blocksAi,
  });

  Map<String, dynamic> toMap() => {
    'code': code,
    'label': label,
    'message': message,
    'blocks_ai': blocksAi,
  };

  factory PromptPrivacyFinding.fromMap(Map<String, dynamic> map) {
    return PromptPrivacyFinding(
      code: map['code']?.toString() ?? '',
      label: map['label']?.toString() ?? 'Privacy concern',
      message: map['message']?.toString() ?? '',
      blocksAi: map['blocks_ai'] == true,
    );
  }
}

class PromptCoachAnalysis {
  final PromptRubricScore scores;
  final List<String> strengths;
  final List<String> suggestions;
  final List<String> guidingQuestions;
  final List<PromptPrivacyFinding> privacyFindings;
  final String summary;

  const PromptCoachAnalysis({
    required this.scores,
    required this.strengths,
    required this.suggestions,
    required this.guidingQuestions,
    required this.privacyFindings,
    required this.summary,
  });

  bool get blocksAi => privacyFindings.any((finding) => finding.blocksAi);

  Map<String, dynamic> toMap() => {
    'scores': scores.toMap(),
    'strengths': strengths,
    'suggestions': suggestions,
    'guiding_questions': guidingQuestions,
    'privacy_findings': privacyFindings.map((item) => item.toMap()).toList(),
    'summary': summary,
  };
}

class PromptAiGuidance {
  final String summary;
  final List<String> focusAreas;
  final List<String> guidingQuestions;
  final List<String> reasoningNotes;
  final String nextChallenge;
  final String responsibleUseReminder;

  const PromptAiGuidance({
    required this.summary,
    required this.focusAreas,
    required this.guidingQuestions,
    required this.reasoningNotes,
    required this.nextChallenge,
    required this.responsibleUseReminder,
  });

  factory PromptAiGuidance.fromMap(Map<String, dynamic> map) {
    List<String> list(String key) {
      final raw = map[key];
      if (raw is! List) return const [];
      return raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .take(5)
          .toList(growable: false);
    }

    return PromptAiGuidance(
      summary: map['summary']?.toString().trim() ?? '',
      focusAreas: list('focus_areas'),
      guidingQuestions: list('guiding_questions'),
      reasoningNotes: list('reasoning_notes'),
      nextChallenge: map['next_challenge']?.toString().trim() ?? '',
      responsibleUseReminder:
          map['responsible_use_reminder']?.toString().trim() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'summary': summary,
    'focus_areas': focusAreas,
    'guiding_questions': guidingQuestions,
    'reasoning_notes': reasoningNotes,
    'next_challenge': nextChallenge,
    'responsible_use_reminder': responsibleUseReminder,
  };
}

class PromptCoachUsage {
  final int used;
  final int limit;
  final DateTime? resetAt;

  const PromptCoachUsage({
    required this.used,
    required this.limit,
    this.resetAt,
  });

  factory PromptCoachUsage.initial({int limit = 3}) =>
      PromptCoachUsage(used: 0, limit: limit);

  factory PromptCoachUsage.fromMap(Map<String, dynamic> map) {
    int parseInt(dynamic value, {int fallback = 0}) {
      if (value is int) return value;
      if (value is num) return value.round();
      return int.tryParse(value?.toString() ?? '') ?? fallback;
    }

    return PromptCoachUsage(
      used: parseInt(map['used']).clamp(0, 999),
      limit: parseInt(map['limit'], fallback: 3).clamp(1, 100),
      resetAt: DateTime.tryParse(map['reset_at']?.toString() ?? ''),
    );
  }

  int get remaining => (limit - used).clamp(0, limit);
  bool get exhausted => remaining <= 0;
}

class PromptCoachServiceStatus {
  final bool available;
  final PromptCoachUsage usage;

  const PromptCoachServiceStatus({
    required this.available,
    required this.usage,
  });

  factory PromptCoachServiceStatus.fromMap(Map<String, dynamic> map) {
    final rawUsage = map['usage'];
    return PromptCoachServiceStatus(
      available: map['available'] == true,
      usage: rawUsage is Map
          ? PromptCoachUsage.fromMap(Map<String, dynamic>.from(rawUsage))
          : PromptCoachUsage.initial(),
    );
  }
}

class PromptAiGuidanceResult {
  final PromptAiGuidance guidance;
  final PromptCoachUsage usage;

  const PromptAiGuidanceResult({
    required this.guidance,
    required this.usage,
  });
}

class PromptCoachRevision {
  final String id;
  final String sessionId;
  final int revisionNumber;
  final String promptText;
  final PromptCoachMode mode;
  final PromptRubricScore scores;
  final List<PromptPrivacyFinding> privacyFindings;
  final PromptAiGuidance? aiGuidance;
  final DateTime? createdAt;

  const PromptCoachRevision({
    required this.id,
    required this.sessionId,
    required this.revisionNumber,
    required this.promptText,
    required this.mode,
    required this.scores,
    required this.privacyFindings,
    required this.aiGuidance,
    this.createdAt,
  });

  factory PromptCoachRevision.fromMap(Map<String, dynamic> map) {
    final rubric = map['rubric'];
    final privacy = map['privacy_flags'];
    final ai = map['ai_guidance'];
    return PromptCoachRevision(
      id: map['id']?.toString() ?? '',
      sessionId: map['session_id']?.toString() ?? '',
      revisionNumber: _asInt(map['revision_number'], fallback: 1),
      promptText: map['prompt_text']?.toString() ?? '',
      mode: PromptCoachModeX.fromDatabase(map['mode']?.toString()),
      scores: rubric is Map
          ? PromptRubricScore.fromMap(Map<String, dynamic>.from(rubric))
          : PromptRubricScore.zero(),
      privacyFindings: privacy is List
          ? privacy
                .whereType<Map>()
                .map(
                  (item) => PromptPrivacyFinding.fromMap(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
      aiGuidance: ai is Map
          ? PromptAiGuidance.fromMap(Map<String, dynamic>.from(ai))
          : null,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
    );
  }
}

class PromptCoachSessionSummary {
  final String id;
  final String title;
  final LearningTopic? focusTopic;
  final int revisionCount;
  final int firstScore;
  final int latestScore;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PromptCoachSessionSummary({
    required this.id,
    required this.title,
    required this.focusTopic,
    required this.revisionCount,
    required this.firstScore,
    required this.latestScore,
    this.createdAt,
    this.updatedAt,
  });

  factory PromptCoachSessionSummary.fromMap(Map<String, dynamic> map) {
    return PromptCoachSessionSummary(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Prompt revision session',
      focusTopic: LearningTopicX.fromId(map['focus_topic']?.toString()),
      revisionCount: _asInt(map['revision_count']),
      firstScore: _asInt(map['first_score']).clamp(0, 100),
      latestScore: _asInt(map['latest_score']).clamp(0, 100),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? ''),
    );
  }

  int get improvement => latestScore - firstScore;
}

class PromptCoachSaveResult {
  final String sessionId;
  final String revisionId;
  final int revisionNumber;
  final int masteryEvidenceCount;

  const PromptCoachSaveResult({
    required this.sessionId,
    required this.revisionId,
    required this.revisionNumber,
    required this.masteryEvidenceCount,
  });

  factory PromptCoachSaveResult.fromMap(Map<String, dynamic> map) {
    return PromptCoachSaveResult(
      sessionId: map['session_id']?.toString() ?? '',
      revisionId: map['revision_id']?.toString() ?? '',
      revisionNumber: _asInt(map['revision_number'], fallback: 1),
      masteryEvidenceCount: _asInt(map['mastery_evidence_count']),
    );
  }
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}
