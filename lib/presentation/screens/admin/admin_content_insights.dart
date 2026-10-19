import '../../../data/models/content_item.dart';
import '../../../data/models/learning_topic.dart';

enum ContentAttention { all, drafts, reviewDue, topicUnassigned, practice }

class AdminContentFilter {
  final ContentType? type;
  final ContentStatus? status;
  final LearningTopic? topic;
  final ContentAttention attention;
  final String query;
  final String? itemId;
  const AdminContentFilter({
    this.type,
    this.status,
    this.topic,
    this.attention = ContentAttention.all,
    this.query = '',
    this.itemId,
  });
}

bool contentReviewDue(ContentItem item, DateTime now) {
  if (item.status != ContentStatus.published || item.reviewDate == null) {
    return false;
  }
  final date = item.reviewDate!.toLocal();
  final today = now.toLocal();
  return !DateTime(
    date.year,
    date.month,
    date.day,
  ).isAfter(DateTime(today.year, today.month, today.day));
}

bool matchesContentAttention(
  ContentItem item,
  ContentAttention attention,
  DateTime now,
) => switch (attention) {
  ContentAttention.all => true,
  ContentAttention.practice =>
    item.type == ContentType.quiz || item.type == ContentType.activity,
  ContentAttention.drafts => item.status == ContentStatus.draft,
  ContentAttention.reviewDue => contentReviewDue(item, now),
  ContentAttention.topicUnassigned =>
    item.status != ContentStatus.archived &&
        (item.type == ContentType.lesson || item.type == ContentType.quiz) &&
        item.adaptiveTopic == null,
};
