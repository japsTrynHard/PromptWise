import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/learning_topic.dart';
import '../models/prompt_coach.dart';

class PromptCoachRepository {
  final SupabaseClient _client;

  const PromptCoachRepository(this._client);

  Future<PromptCoachSaveResult> recordRevision({
    String? sessionId,
    required String prompt,
    required PromptCoachMode mode,
    required PromptCoachAnalysis analysis,
    PromptAiGuidance? aiGuidance,
    LearningTopic? focusTopic,
  }) async {
    final response = await _client.rpc(
      'record_prompt_coach_revision',
      params: {
        'p_session_id': sessionId,
        'p_prompt_text': prompt.trim(),
        'p_mode': mode.databaseValue,
        'p_rubric': analysis.scores.toMap(),
        'p_privacy_flags': analysis.privacyFindings
            .map((item) => item.toMap())
            .toList(growable: false),
        'p_standard_feedback': {
          'summary': analysis.summary,
          'strengths': analysis.strengths,
          'suggestions': analysis.suggestions,
          'guiding_questions': analysis.guidingQuestions,
        },
        'p_ai_guidance': aiGuidance?.toMap(),
        'p_focus_topic': focusTopic?.id,
      },
    );

    if (response is Map) {
      return PromptCoachSaveResult.fromMap(
        Map<String, dynamic>.from(response),
      );
    }
    if (response is List && response.isNotEmpty && response.first is Map) {
      return PromptCoachSaveResult.fromMap(
        Map<String, dynamic>.from(response.first as Map),
      );
    }
    throw StateError('Prompt Coach revision could not be saved.');
  }

  Future<List<PromptCoachSessionSummary>> fetchRecentSessions({
    int limit = 8,
  }) async {
    final response = await _client.rpc(
      'get_prompt_coach_recent_sessions',
      params: {'p_limit': limit},
    );

    return (response as List)
        .whereType<Map>()
        .map(
          (row) => PromptCoachSessionSummary.fromMap(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList(growable: false);
  }

  Future<List<PromptCoachRevision>> fetchSessionRevisions({
    required String userId,
    required String sessionId,
  }) async {
    final response = await _client
        .from('prompt_coach_revisions')
        .select(
          'id, session_id, revision_number, prompt_text, mode, rubric, '
          'privacy_flags, ai_guidance, created_at',
        )
        .eq('user_id', userId)
        .eq('session_id', sessionId)
        .order('revision_number');

    return (response as List)
        .whereType<Map>()
        .map(
          (row) => PromptCoachRevision.fromMap(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList(growable: false);
  }

}
