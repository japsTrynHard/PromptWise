import './learning_topic.dart';

class ContentSource {
  final String id;
  final String name;
  final String sourceUrl;
  final String? feedUrl;
  final String sourceType;
  final int trustLevel;
  final bool enabled;
  final DateTime? lastCheckedAt;

  const ContentSource({
    required this.id,
    required this.name,
    required this.sourceUrl,
    required this.feedUrl,
    required this.sourceType,
    required this.trustLevel,
    required this.enabled,
    this.lastCheckedAt,
  });

  factory ContentSource.fromMap(Map<String, dynamic> map) => ContentSource(
    id: map['id']?.toString() ?? '',
    name: map['name']?.toString() ?? '',
    sourceUrl: map['source_url']?.toString() ?? '',
    feedUrl: _nullableString(map['feed_url']),
    sourceType: map['source_type']?.toString() ?? 'page',
    trustLevel: _asInt(map['trust_level'], fallback: 3).clamp(1, 5),
    enabled: map['enabled'] == true,
    lastCheckedAt: _asDate(map['last_checked_at']),
  );
}

class AutomationSettings {
  final bool enabled;
  final int maxArticlesPerRun;
  final int maxDraftsPerDay;
  final int monthlyDraftCap;
  final int manualCooldownMinutes;
  final int maxPendingDrafts;
  final int maxPendingQuestions;
  final int draftArchiveDays;
  final int rejectedDeleteDays;
  final int archivedDeleteDays;
  final DateTime? lastManualRunAt;

  const AutomationSettings({
    required this.enabled,
    required this.maxArticlesPerRun,
    required this.maxDraftsPerDay,
    required this.monthlyDraftCap,
    required this.manualCooldownMinutes,
    required this.maxPendingDrafts,
    required this.maxPendingQuestions,
    required this.draftArchiveDays,
    required this.rejectedDeleteDays,
    required this.archivedDeleteDays,
    this.lastManualRunAt,
  });

  factory AutomationSettings.defaults() => const AutomationSettings(
    enabled: true,
    maxArticlesPerRun: 3,
    maxDraftsPerDay: 3,
    monthlyDraftCap: 100,
    manualCooldownMinutes: 30,
    maxPendingDrafts: 30,
    maxPendingQuestions: 100,
    draftArchiveDays: 30,
    rejectedDeleteDays: 7,
    archivedDeleteDays: 90,
  );

  factory AutomationSettings.fromMap(Map<String, dynamic> map) =>
      AutomationSettings(
        enabled: map['enabled'] != false,
        maxArticlesPerRun: _asInt(
          map['max_articles_per_run'],
          fallback: 3,
        ).clamp(1, 10),
        maxDraftsPerDay: _asInt(
          map['max_drafts_per_day'],
          fallback: 3,
        ).clamp(1, 20),
        monthlyDraftCap: _asInt(
          map['monthly_draft_cap'],
          fallback: 100,
        ).clamp(1, 1000),
        manualCooldownMinutes: _asInt(
          map['manual_cooldown_minutes'],
          fallback: 30,
        ).clamp(1, 1440),
        maxPendingDrafts: _asInt(
          map['max_pending_drafts'],
          fallback: 30,
        ).clamp(5, 200),
        maxPendingQuestions: _asInt(
          map['max_pending_questions'],
          fallback: 100,
        ).clamp(20, 1000),
        draftArchiveDays: _asInt(
          map['draft_archive_days'],
          fallback: 30,
        ).clamp(7, 180),
        rejectedDeleteDays: _asInt(
          map['rejected_delete_days'],
          fallback: 7,
        ).clamp(1, 60),
        archivedDeleteDays: _asInt(
          map['archived_delete_days'],
          fallback: 90,
        ).clamp(30, 365),
        lastManualRunAt: _asDate(map['last_manual_run_at']),
      );
}

class QueueLifecycleStats {
  final int pendingDrafts;
  final int pendingQuestions;
  final int archivedDrafts;
  final int expiringDraftsSoon;
  final int expiringQuestionsSoon;
  final int maxPendingDrafts;
  final int maxPendingQuestions;
  final int draftArchiveDays;
  final int rejectedDeleteDays;
  final int archivedDeleteDays;

  const QueueLifecycleStats({
    required this.pendingDrafts,
    required this.pendingQuestions,
    required this.archivedDrafts,
    required this.expiringDraftsSoon,
    required this.expiringQuestionsSoon,
    required this.maxPendingDrafts,
    required this.maxPendingQuestions,
    required this.draftArchiveDays,
    required this.rejectedDeleteDays,
    required this.archivedDeleteDays,
  });

  factory QueueLifecycleStats.empty() => const QueueLifecycleStats(
        pendingDrafts: 0,
        pendingQuestions: 0,
        archivedDrafts: 0,
        expiringDraftsSoon: 0,
        expiringQuestionsSoon: 0,
        maxPendingDrafts: 30,
        maxPendingQuestions: 100,
        draftArchiveDays: 30,
        rejectedDeleteDays: 7,
        archivedDeleteDays: 90,
      );

  factory QueueLifecycleStats.fromMap(Map<String, dynamic> map) =>
      QueueLifecycleStats(
        pendingDrafts: _asInt(map['pending_drafts']),
        pendingQuestions: _asInt(map['pending_questions']),
        archivedDrafts: _asInt(map['archived_drafts']),
        expiringDraftsSoon: _asInt(map['expiring_drafts_soon']),
        expiringQuestionsSoon: _asInt(map['expiring_questions_soon']),
        maxPendingDrafts: _asInt(map['max_pending_drafts'], fallback: 30),
        maxPendingQuestions: _asInt(
          map['max_pending_questions'],
          fallback: 100,
        ),
        draftArchiveDays: _asInt(map['draft_archive_days'], fallback: 30),
        rejectedDeleteDays: _asInt(
          map['rejected_delete_days'],
          fallback: 7,
        ),
        archivedDeleteDays: _asInt(
          map['archived_delete_days'],
          fallback: 90,
        ),
      );
}

class GeneratedContentDraft {
  final String id;
  final String title;
  final String summary;
  final LearningTopic topic;
  final int targetLevel;
  final String sourceName;
  final String sourceUrl;
  final DateTime? sourcePublishedAt;
  final String status;
  final List<String> objectives;
  final List<String> lessonSections;
  final int questionCount;
  final DateTime? createdAt;

  const GeneratedContentDraft({
    required this.id,
    required this.title,
    required this.summary,
    required this.topic,
    required this.targetLevel,
    required this.sourceName,
    required this.sourceUrl,
    required this.sourcePublishedAt,
    required this.status,
    required this.objectives,
    required this.lessonSections,
    required this.questionCount,
    this.createdAt,
  });

  factory GeneratedContentDraft.fromMap(Map<String, dynamic> map) {
    final topic = LearningTopicX.fromId(map['topic_id']?.toString()) ??
        LearningTopic.verification;
    final payload = map['draft_payload'];
    final payloadMap = payload is Map
        ? Map<String, dynamic>.from(payload)
        : const <String, dynamic>{};
    final objectives = _stringList(payloadMap['objectives']);
    final sections = _stringList(payloadMap['lesson_sections']);
    final rawQuestions = payloadMap['questions'];
    final questionCount = rawQuestions is List ? rawQuestions.length : 0;
    return GeneratedContentDraft(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? payloadMap['title']?.toString() ?? '',
      summary:
          map['summary']?.toString() ?? payloadMap['summary']?.toString() ?? '',
      topic: topic,
      targetLevel: _asInt(map['target_level'], fallback: 2).clamp(1, 5),
      sourceName: map['source_name']?.toString() ?? '',
      sourceUrl: map['source_url']?.toString() ?? '',
      sourcePublishedAt: _asDate(map['source_published_at']),
      status: map['status']?.toString() ?? 'draft',
      objectives: objectives,
      lessonSections: sections,
      questionCount: questionCount,
      createdAt: _asDate(map['created_at']),
    );
  }
}

class LearningContentHealth {
  final LearningTopic topic;
  final int lessons;
  final int objectives;
  final int publishedQuestions;
  final Map<int, int> questionsByLevel;

  const LearningContentHealth({
    required this.topic,
    required this.lessons,
    required this.objectives,
    required this.publishedQuestions,
    required this.questionsByLevel,
  });

  factory LearningContentHealth.fromMap(Map<String, dynamic> map) {
    final topic = LearningTopicX.fromId(map['topic_id']?.toString());
    if (topic == null) {
      throw const FormatException('Unknown learning-content health topic.');
    }
    return LearningContentHealth(
      topic: topic,
      lessons: _asInt(map['lesson_count']),
      objectives: _asInt(map['objective_count']),
      publishedQuestions: _asInt(map['published_question_count']),
      questionsByLevel: {
        for (var level = 1; level <= 5; level++)
          level: _asInt(map['level_${level}_questions']),
      },
    );
  }
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value.map((item) {
    if (item is Map) {
      final row = Map<String, dynamic>.from(item);
      final title = row['title']?.toString().trim() ?? '';
      if (title.isNotEmpty) return title;
      final description = row['description']?.toString().trim() ?? '';
      if (description.isNotEmpty) return description;
    }
    return item.toString();
  }).where((item) => item.trim().isNotEmpty).toList(growable: false);
}

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

class QuestionBankReviewItem {
  final String id;
  final String questionCode;
  final String? sourceContentId;
  final LearningTopic topic;
  final String questionType;
  final String stem;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final int difficulty;
  final String status;
  final String validationStatus;
  final double qualityScore;
  final String generatedBy;
  final String? sourceUrl;
  final DateTime? createdAt;

  const QuestionBankReviewItem({
    required this.id,
    required this.questionCode,
    required this.sourceContentId,
    required this.topic,
    required this.questionType,
    required this.stem,
    required this.options,
    required this.correctIndex,
    required this.explanation,
    required this.difficulty,
    required this.status,
    required this.validationStatus,
    required this.qualityScore,
    required this.generatedBy,
    required this.sourceUrl,
    this.createdAt,
  });

  factory QuestionBankReviewItem.fromMap(Map<String, dynamic> map) {
    final topic = LearningTopicX.fromId(map['topic_id']?.toString());
    if (topic == null) {
      throw const FormatException('Unknown question-bank topic.');
    }
    final rawOptions = map['options'];
    final options = rawOptions is List
        ? rawOptions.map((value) => value.toString()).toList(growable: false)
        : const <String>[];
    return QuestionBankReviewItem(
      id: map['id']?.toString() ?? '',
      questionCode: map['question_code']?.toString() ?? '',
      sourceContentId: _nullableString(map['source_content_id']),
      topic: topic,
      questionType: map['question_type']?.toString() ?? 'scenario',
      stem: map['stem']?.toString() ?? '',
      options: options,
      correctIndex: _asInt(map['correct_index']).clamp(0, 3),
      explanation: map['explanation']?.toString() ?? '',
      difficulty: _asInt(map['difficulty'], fallback: 1).clamp(1, 5),
      status: map['status']?.toString() ?? 'draft',
      validationStatus: map['validation_status']?.toString() ?? 'needs_review',
      qualityScore: _asDouble(map['quality_score']),
      generatedBy: map['generated_by']?.toString() ?? 'manual',
      sourceUrl: _nullableString(map['source_url']),
      createdAt: _asDate(map['created_at']),
    );
  }

  QuestionBankReviewItem copyWith({
    String? stem,
    List<String>? options,
    int? correctIndex,
    String? explanation,
    int? difficulty,
    String? questionType,
  }) {
    return QuestionBankReviewItem(
      id: id,
      questionCode: questionCode,
      sourceContentId: sourceContentId,
      topic: topic,
      questionType: questionType ?? this.questionType,
      stem: stem ?? this.stem,
      options: options ?? this.options,
      correctIndex: correctIndex ?? this.correctIndex,
      explanation: explanation ?? this.explanation,
      difficulty: difficulty ?? this.difficulty,
      status: status,
      validationStatus: validationStatus,
      qualityScore: qualityScore,
      generatedBy: generatedBy,
      sourceUrl: sourceUrl,
      createdAt: createdAt,
    );
  }
}

double _asDouble(dynamic value, {double fallback = 0}) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}
