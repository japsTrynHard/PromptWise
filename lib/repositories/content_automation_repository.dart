import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/content_automation.dart';

class ContentAutomationRepository {
  final SupabaseClient _client;

  const ContentAutomationRepository(this._client);

  Future<List<ContentSource>> fetchSources() async {
    final response = await _client
        .from('content_sources')
        .select()
        .order('trust_level', ascending: false)
        .order('name');
    return (response as List)
        .map(
          (row) => ContentSource.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<AutomationSettings> fetchSettings() async {
    final response = await _client
        .from('automation_settings')
        .select()
        .eq('id', 1)
        .maybeSingle();
    if (response == null) return AutomationSettings.defaults();
    return AutomationSettings.fromMap(Map<String, dynamic>.from(response));
  }

  Future<List<GeneratedContentDraft>> fetchDrafts() async {
    final response = await _client
        .from('generated_content_drafts')
        .select()
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
          LearningContentHealth.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
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
        .eq('id', sourceId);
  }

  Future<void> updateSettings({
    required bool enabled,
    required int maxArticlesPerRun,
    required int maxDraftsPerDay,
    required int monthlyDraftCap,
    required int maxPendingDrafts,
    required int maxPendingQuestions,
    required int draftArchiveDays,
  }) async {
    await _client.from('automation_settings').update({
      'enabled': enabled,
      'max_articles_per_run': maxArticlesPerRun,
      'max_drafts_per_day': maxDraftsPerDay,
      'monthly_draft_cap': monthlyDraftCap,
      'max_pending_drafts': maxPendingDrafts,
      'max_pending_questions': maxPendingQuestions,
      'draft_archive_days': draftArchiveDays,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', 1);
  }

  Future<QueueLifecycleStats> fetchQueueHealth() async {
    final response = await _client.rpc('get_phase7_queue_health');
    if (response is List && response.isNotEmpty) {
      return QueueLifecycleStats.fromMap(
        Map<String, dynamic>.from(response.first as Map),
      );
    }
    if (response is Map) {
      return QueueLifecycleStats.fromMap(
        Map<String, dynamic>.from(response),
      );
    }
    return QueueLifecycleStats.empty();
  }

  Future<String> runAutomationNow() async {
    final response = await _client.functions.invoke(
      'content-automation',
      body: const {'mode': 'manual'},
    );
    final data = response.data;
    if (response.status < 200 || response.status >= 300) {
      final detail = data is Map
          ? data['error']?.toString() ?? data['message']?.toString()
          : data?.toString();
      throw StateError(
        detail == null || detail.trim().isEmpty
            ? 'Content automation could not be started.'
            : detail,
      );
    }
    if (data is Map) {
      return data['message']?.toString() ?? 'Automation completed.';
    }
    return 'Automation completed.';
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
        .limit(500);
    final result = <QuestionBankReviewItem>[];
    for (final row in response as List) {
      try {
        result.add(
          QuestionBankReviewItem.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
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
          QuestionBankReviewItem.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
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
