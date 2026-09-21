import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/content_automation.dart';
import '../models/learning_topic.dart';

class ContentAutomationRepository {
  final SupabaseClient _client;

  const ContentAutomationRepository(this._client);

  Future<List<ContentSource>> fetchSources() async {
    final response = await _client
        .from('content_sources')
        .select(
          'id,name,source_url,feed_url,source_type,trust_level,enabled,last_checked_at',
        )
        .order('trust_level', ascending: false)
        .order('name');
    return (response as List)
        .map(
          (row) => ContentSource.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  Future<AutomationSettings> fetchSettings() async {
    final response = await _client
        .from('automation_settings')
        .select(
          'enabled,max_articles_per_run,max_drafts_per_day,monthly_draft_cap,manual_cooldown_minutes,max_pending_drafts,max_pending_questions,draft_archive_days,rejected_delete_days,archived_delete_days,last_manual_run_at,focus_topics',
        )
        .eq('id', 1)
        .maybeSingle();
    if (response == null) return AutomationSettings.defaults();
    return AutomationSettings.fromMap(Map<String, dynamic>.from(response));
  }

  Future<List<GeneratedContentDraft>> fetchDrafts() async {
    final response = await _client
        .from('generated_content_drafts')
        .select(
          'id,title,summary,topic_id,target_level,source_name,source_url,source_published_at,status,draft_payload,created_at',
        )
        .eq('status', 'draft')
        .order('created_at', ascending: false)
        .limit(50);
    return (response as List)
        .map(
          (row) => GeneratedContentDraft.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<List<LearningContentHealth>> fetchContentHealth() async {
    final response = await _client
        .from('phase7_content_health')
        .select()
        .order('topic_id');
    final result = <LearningContentHealth>[];
    for (final row in response as List) {
      try {
        result.add(
          LearningContentHealth.fromMap(Map<String, dynamic>.from(row as Map)),
        );
      } on FormatException {
        // Ignore malformed aggregation rows.
      }
    }
    return result;
  }

  Future<void> setSourceEnabled(String sourceId, bool enabled) async {
    await _client
        .from('content_sources')
        .update({'enabled': enabled})
        .eq('id', sourceId)
        .select('id')
        .single();
  }

  Future<void> updateSettings({
    required bool enabled,
    required int maxArticlesPerRun,
    required int maxDraftsPerDay,
    required int monthlyDraftCap,
    required int maxPendingDrafts,
    required int maxPendingQuestions,
    required int draftArchiveDays,
    required List<LearningTopic> focusTopics,
  }) async {
    await _client
        .from('automation_settings')
        .update({
          'enabled': enabled,
          'focus_topics': focusTopics.map((topic) => topic.id).toList(),
          'max_articles_per_run': maxArticlesPerRun,
          'max_drafts_per_day': maxDraftsPerDay,
          'monthly_draft_cap': monthlyDraftCap,
          'max_pending_drafts': maxPendingDrafts,
          'max_pending_questions': maxPendingQuestions,
          'draft_archive_days': draftArchiveDays,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', 1)
        .select('id')
        .single();
    // .single() fails if RLS/permissions prevented the update; do not report
    // success when no administrator settings row was actually modified.
  }

  Future<QueueLifecycleStats> fetchQueueHealth() async {
    final response = await _client.rpc('get_phase7_queue_health');
    if (response is List && response.isNotEmpty) {
      return QueueLifecycleStats.fromMap(
        Map<String, dynamic>.from(response.first as Map),
      );
    }
    if (response is Map) {
      return QueueLifecycleStats.fromMap(Map<String, dynamic>.from(response));
    }
    return QueueLifecycleStats.empty();
  }

  Future<String> runAutomationNow(List<LearningTopic> focusTopics) async {
    if (focusTopics.isEmpty) {
      throw StateError('Choose at least one focus area for Generate Now.');
    }

    return _invokeAutomation(
      body: {
        'mode': 'manual',
        'focus_topics': focusTopics.map((topic) => topic.id).toList(),
      },
      failureMessage: 'Content automation could not be started.',
    );
  }

  Future<String> runVerificationDraftsNow() async {
    return _invokeAutomation(
      body: const {'mode': 'manual', 'target': 'verification'},
      failureMessage: 'Verification draft generation could not be started.',
    );
  }

  Future<String> _invokeAutomation({
    required Map<String, dynamic> body,
    required String failureMessage,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'content-automation',
        body: body,
      );
      final data = response.data;
      if (response.status < 200 || response.status >= 300 || data is! Map) {
        throw StateError(_responseMessage(data, failureMessage));
      }
      // Partial runs can save drafts, but must not be shown as full success.
      if (data['partial'] == true ||
          data['success'] == false ||
          data['error'] != null) {
        throw StateError(_responseMessage(data, failureMessage));
      }
      return data['message']?.toString() ?? 'Automation completed.';
    } on FunctionException catch (error) {
      // The SDK throws on non-2xx before returning a FunctionResponse.
      // Preserve the server's cooldown/configuration details for the admin.
      throw StateError(_responseMessage(error.details, failureMessage));
    }
  }

  String _responseMessage(dynamic data, String fallback) {
    if (data is Map) {
      final message = (data['error'] ?? data['message'])?.toString().trim();
      if (message != null && message.isNotEmpty) return message;
    }
    return fallback;
  }

  Future<void> publishDraft(String draftId) async {
    await _client.rpc(
      'publish_generated_content_draft',
      params: {'p_draft_id': draftId},
    );
  }

  Future<void> rejectDraft(String draftId) async {
    await _client.rpc(
      'reject_generated_content_draft',
      params: {'p_draft_id': draftId},
    );
  }

  Future<List<QuestionBankReviewItem>> fetchApprovedQuestions() async {
    final response = await _client
        .from('question_bank')
        .select(
          'id, question_code, source_content_id, topic_id, question_type, '
          'stem, options, correct_index, explanation, difficulty, status, '
          'validation_status, quality_score, generated_by, source_url, created_at',
        )
        .eq('validation_status', 'verified')
        .neq('status', 'archived')
        .order('created_at', ascending: false)
        .limit(150);
    final result = <QuestionBankReviewItem>[];
    for (final row in response as List) {
      try {
        result.add(
          QuestionBankReviewItem.fromMap(Map<String, dynamic>.from(row as Map)),
        );
      } on FormatException {
        // Ignore malformed rows instead of breaking the approved bank browser.
      }
    }
    return result;
  }

  Future<List<QuestionBankReviewItem>> fetchQuestionReviewQueue() async {
    final response = await _client
        .from('question_bank')
        .select(
          'id, question_code, source_content_id, topic_id, question_type, '
          'stem, options, correct_index, explanation, difficulty, status, '
          'validation_status, quality_score, generated_by, source_url, created_at',
        )
        .eq('validation_status', 'needs_review')
        .neq('status', 'archived')
        .order('created_at', ascending: false)
        .limit(100);
    final result = <QuestionBankReviewItem>[];
    for (final row in response as List) {
      try {
        result.add(
          QuestionBankReviewItem.fromMap(Map<String, dynamic>.from(row as Map)),
        );
      } on FormatException {
        // Ignore malformed draft questions instead of breaking Learning Studio.
      }
    }
    return result;
  }

  Future<void> verifyQuestion(QuestionBankReviewItem question) async {
    await _client.rpc(
      'review_question_bank_item',
      params: {
        'p_question_id': question.id,
        'p_stem': question.stem.trim(),
        'p_options': question.options.map((value) => value.trim()).toList(),
        'p_correct_index': question.correctIndex,
        'p_explanation': question.explanation.trim(),
        'p_difficulty': question.difficulty,
        'p_question_type': question.questionType,
        'p_action': 'verify',
      },
    );
  }

  Future<void> rejectQuestion(String questionId) async {
    await _client.rpc(
      'review_question_bank_item',
      params: {
        'p_question_id': questionId,
        'p_stem': 'Rejected question',
        'p_options': const ['A', 'B', 'C', 'D'],
        'p_correct_index': 0,
        'p_explanation': 'Rejected by an administrator during quality review.',
        'p_difficulty': 1,
        'p_question_type': 'concept',
        'p_action': 'reject',
      },
    );
  }
}
