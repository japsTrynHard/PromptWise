import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/learning_progression.dart';
import '../models/learning_topic.dart';

class LearningProgressionRepository {
  final SupabaseClient _client;

  const LearningProgressionRepository(this._client);

  Future<List<LearningObjective>> fetchObjectives() async {
    final response = await _client
        .from('learning_objectives')
        .select()
        .eq('status', 'published')
        .order('topic_id')
        .order('required_level')
        .order('sort_order');

    final objectives = <LearningObjective>[];
    for (final row in response as List) {
      try {
        objectives.add(
          LearningObjective.fromMap(Map<String, dynamic>.from(row as Map)),
        );
      } on FormatException {
        // Ignore malformed content rows rather than blocking learner access.
      }
    }
    return objectives;
  }

  Future<List<LearnerTopicRank>> fetchTopicRanks(String userId) async {
    final response = await _client
        .from('learner_topic_progression')
        .select()
        .eq('user_id', userId)
        .order('topic_id');

    final ranks = <LearnerTopicRank>[];
    for (final row in response as List) {
      try {
        ranks.add(
          LearnerTopicRank.fromMap(Map<String, dynamic>.from(row as Map)),
        );
      } on FormatException {
        // Ignore malformed rows; controller supplies a safe Foundation default.
      }
    }
    return ranks;
  }

  Future<KnowledgeCheckSession> createKnowledgeCheck({
    required int questionCount,
    LearningTopic? focusTopic,
    String mode = 'adaptive',
  }) async {
    final response = await _client.rpc(
      'create_adaptive_knowledge_check',
      params: {
        'p_question_count': questionCount.clamp(5, 15),
        'p_focus_topic': focusTopic?.id,
        'p_mode': mode,
      },
    );

    final map = _jsonMap(response);
    final session = KnowledgeCheckSession.fromMap(map);
    if (session.id.isEmpty || session.questions.isEmpty) {
      throw StateError(
        'No eligible knowledge-check questions are available right now.',
      );
    }
    return session;
  }

  Future<KnowledgeAnswerFeedback> answerQuestion({
    required String sessionId,
    required String questionId,
    required int selectedIndex,
  }) async {
    final response = await _client.rpc(
      'record_learning_question_answer',
      params: {
        'p_session_id': sessionId,
        'p_question_id': questionId,
        'p_selected_index': selectedIndex,
      },
    );
    return KnowledgeAnswerFeedback.fromMap(_jsonMap(response));
  }

  Future<void> abandonKnowledgeCheck(String sessionId) async {
    await _client.rpc(
      'abandon_adaptive_knowledge_check',
      params: {'p_session_id': sessionId},
    );
  }

  Future<KnowledgeCheckSummary> completeKnowledgeCheck(String sessionId) async {
    final response = await _client.rpc(
      'complete_adaptive_knowledge_check',
      params: {'p_session_id': sessionId},
    );
    return KnowledgeCheckSummary.fromMap(_jsonMap(response));
  }

  Future<void> refreshProgression() async {
    await _client.rpc('refresh_my_learning_progression');
  }

  Map<String, dynamic> _jsonMap(dynamic response) {
    if (response is Map) return Map<String, dynamic>.from(response);
    if (response is List && response.isNotEmpty && response.first is Map) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    throw const FormatException('Unexpected server response.');
  }
}
