import 'learning_topic.dart';

enum ContentType { module, lesson, quiz, activity, awareness }

enum ContentStatus { draft, published, archived }

extension ContentTypeX on ContentType {
  String get databaseValue => name;

  String get label => switch (this) {
    ContentType.module => 'Module',
    ContentType.lesson => 'Lesson',
    ContentType.quiz => 'Quiz',
    ContentType.activity => 'Verification activity',
    ContentType.awareness => 'Awareness post',
  };

  static ContentType fromDatabase(String? value) {
    return ContentType.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ContentType.module,
    );
  }
}

extension ContentStatusX on ContentStatus {
  String get databaseValue => name;

  String get label => switch (this) {
    ContentStatus.draft => 'Draft',
    ContentStatus.published => 'Published',
    ContentStatus.archived => 'Archived',
  };

  static ContentStatus fromDatabase(String? value) {
    return ContentStatus.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ContentStatus.draft,
    );
  }
}

class ContentItem {
  final String id;
  final ContentType type;
  final String? parentId;
  final String title;
  final String description;
  final String body;
  final String icon;
  final int estimatedMinutes;
  final String? quizId;
  final String question;
  final List<String> options;
  final int? correctIndex;
  final String explanation;
  final String imagePathA;
  final String imagePathB;
  final bool? isAAI;
  final int sortOrder;
  final int learningLevel;
  final LearningTopic? adaptiveTopic;
  final ContentStatus status;
  final int version;
  final String? sourceUrl;
  final DateTime? publicationDate;
  final DateTime? reviewDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ContentItem({
    required this.id,
    required this.type,
    required this.title,
    this.parentId,
    this.description = '',
    this.body = '',
    this.icon = '',
    this.estimatedMinutes = 0,
    this.quizId,
    this.question = '',
    this.options = const [],
    this.correctIndex,
    this.explanation = '',
    this.imagePathA = '',
    this.imagePathB = '',
    this.isAAI,
    this.sortOrder = 0,
    this.learningLevel = 1,
    this.adaptiveTopic,
    this.status = ContentStatus.draft,
    this.version = 1,
    this.sourceUrl,
    this.publicationDate,
    this.reviewDate,
    this.createdAt,
    this.updatedAt,
  });

  factory ContentItem.fromMap(Map<String, dynamic> map) {
    final rawOptions = map['options'];
    return ContentItem(
      id: map['id']?.toString() ?? '',
      type: ContentTypeX.fromDatabase(map['content_type']?.toString()),
      parentId: _nullableString(map['parent_id']),
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      icon: map['icon']?.toString() ?? '',
      estimatedMinutes: _asInt(map['estimated_minutes']),
      quizId: _nullableString(map['quiz_id']),
      question: map['question']?.toString() ?? '',
      options: rawOptions is List
          ? rawOptions.map((value) => value.toString()).toList(growable: false)
          : const [],
      correctIndex: map['correct_index'] == null
          ? null
          : _asInt(map['correct_index']),
      explanation: map['explanation']?.toString() ?? '',
      imagePathA: map['image_path_a']?.toString() ?? '',
      imagePathB: map['image_path_b']?.toString() ?? '',
      isAAI: map['is_a_ai'] as bool?,
      sortOrder: _asInt(map['sort_order']),
      learningLevel: _asInt(map['learning_level'], fallback: 1).clamp(1, 5),
      adaptiveTopic: LearningTopicX.fromId(map['adaptive_topic']?.toString()),
      status: ContentStatusX.fromDatabase(map['status']?.toString()),
      version: _asInt(map['version'], fallback: 1),
      sourceUrl: _nullableString(map['source_url']),
      publicationDate: _asDate(map['publication_date']),
      reviewDate: _asDate(map['review_date']),
      createdAt: _asDate(map['created_at']),
      updatedAt: _asDate(map['updated_at']),
    );
  }

  Map<String, dynamic> toDatabaseMap({bool includeId = true}) {
    return <String, dynamic>{
      if (includeId) 'id': id,
      'content_type': type.databaseValue,
      'parent_id': _nullIfEmpty(parentId),
      'title': title.trim(),
      'description': description.trim(),
      'body': body.trim(),
      'icon': icon.trim(),
      'estimated_minutes': estimatedMinutes,
      'quiz_id': _nullIfEmpty(quizId),
      'question': question.trim(),
      'options': options
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      'correct_index': correctIndex,
      'explanation': explanation.trim(),
      'image_path_a': imagePathA.trim(),
      'image_path_b': imagePathB.trim(),
      'is_a_ai': isAAI,
      'sort_order': sortOrder,
      'learning_level': learningLevel.clamp(1, 5),
      'adaptive_topic': adaptiveTopic?.id,
      'status': status.databaseValue,
      'source_url': _nullIfEmpty(sourceUrl),
      'publication_date': _dateOnly(publicationDate),
      'review_date': _dateOnly(reviewDate),
    };
  }

  ContentItem copyWith({
    String? id,
    ContentType? type,
    String? parentId,
    bool clearParentId = false,
    String? title,
    String? description,
    String? body,
    String? icon,
    int? estimatedMinutes,
    String? quizId,
    bool clearQuizId = false,
    String? question,
    List<String>? options,
    int? correctIndex,
    bool clearCorrectIndex = false,
    String? explanation,
    String? imagePathA,
    String? imagePathB,
    bool? isAAI,
    bool clearIsAAI = false,
    int? sortOrder,
    int? learningLevel,
    LearningTopic? adaptiveTopic,
    bool clearAdaptiveTopic = false,
    ContentStatus? status,
    int? version,
    String? sourceUrl,
    bool clearSourceUrl = false,
    DateTime? publicationDate,
    bool clearPublicationDate = false,
    DateTime? reviewDate,
    bool clearReviewDate = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ContentItem(
      id: id ?? this.id,
      type: type ?? this.type,
      parentId: clearParentId ? null : parentId ?? this.parentId,
      title: title ?? this.title,
      description: description ?? this.description,
      body: body ?? this.body,
      icon: icon ?? this.icon,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      quizId: clearQuizId ? null : quizId ?? this.quizId,
      question: question ?? this.question,
      options: options ?? this.options,
      correctIndex: clearCorrectIndex
          ? null
          : correctIndex ?? this.correctIndex,
      explanation: explanation ?? this.explanation,
      imagePathA: imagePathA ?? this.imagePathA,
      imagePathB: imagePathB ?? this.imagePathB,
      isAAI: clearIsAAI ? null : isAAI ?? this.isAAI,
      sortOrder: sortOrder ?? this.sortOrder,
      learningLevel: learningLevel ?? this.learningLevel,
      adaptiveTopic: clearAdaptiveTopic ? null : adaptiveTopic ?? this.adaptiveTopic,
      status: status ?? this.status,
      version: version ?? this.version,
      sourceUrl: clearSourceUrl ? null : sourceUrl ?? this.sourceUrl,
      publicationDate: clearPublicationDate
          ? null
          : publicationDate ?? this.publicationDate,
      reviewDate: clearReviewDate ? null : reviewDate ?? this.reviewDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String get displayTitle =>
      type == ContentType.quiz && title.trim().isEmpty ? question : title;

  bool get isPublished => status == ContentStatus.published;
}

class ContentVersion {
  final int version;
  final ContentItem snapshot;
  final DateTime? changedAt;
  final String operation;

  const ContentVersion({
    required this.version,
    required this.snapshot,
    required this.operation,
    this.changedAt,
  });

  factory ContentVersion.fromMap(Map<String, dynamic> map) {
    final snapshot = Map<String, dynamic>.from(
      (map['snapshot'] as Map?) ?? const <String, dynamic>{},
    );
    return ContentVersion(
      version: _asInt(map['version'], fallback: 1),
      snapshot: ContentItem.fromMap(snapshot),
      operation: map['operation']?.toString() ?? 'UPDATE',
      changedAt: _asDate(map['changed_at']),
    );
  }
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String? _nullableString(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String? _nullIfEmpty(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? null : text;
}

DateTime? _asDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

String? _dateOnly(DateTime? value) {
  if (value == null) return null;
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
