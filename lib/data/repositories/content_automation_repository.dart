import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/content_automation.dart';
import '../models/learning_topic.dart';
import '../models/verification.dart';

class PartialGenerationException extends StateError {
  PartialGenerationException(super.message);
}

class _DeferredLearningGeneration extends StateError {
  final List<String> topics;
  final int retryAfterSeconds;
  final bool hasSavedDrafts;
  final int newDrafts;
  _DeferredLearningGeneration(
    super.message,
    this.topics,
    this.retryAfterSeconds,
    this.hasSavedDrafts,
    this.newDrafts,
  );
}

class ContentAutomationRepository {
  final SupabaseClient _client;
  final Future<void> Function(Duration) _wait;

  const ContentAutomationRepository(
    this._client, {
    Future<void> Function(Duration) wait = Future<void>.delayed,
  }) : _wait = wait;

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
    int? manualCooldownMinutes,
    required bool enabled,
    required int maxArticlesPerRun,
    required int maxDraftsPerDay,
    required int monthlyDraftCap,
    required int maxPendingDrafts,
    required int maxPendingQuestions,
    required int draftArchiveDays,
    required List<LearningTopic> focusTopics,
  }) async {
    if (manualCooldownMinutes != null &&
        (manualCooldownMinutes < 0 || manualCooldownMinutes > 1440)) {
      throw ArgumentError("Manual cooldown must be from 0 to 1440 minutes.");
    }
    validateScheduledAutomationFocus(
      enabled: enabled,
      focusTopics: focusTopics,
    );
    await _client
        .from('automation_settings')
        .update({
          'enabled': enabled,
          if (manualCooldownMinutes != null)
            'manual_cooldown_minutes': manualCooldownMinutes,
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

  Future<String> runAutomationNow(
    List<LearningTopic> focusTopics, {
    void Function(String)? onProgress,
    bool Function()? shouldContinue,
  }) async {
    if (focusTopics.isEmpty) {
      throw StateError('Choose at least one focus area for Generate Now.');
    }

    var pending = focusTopics.map((topic) => topic.id).toSet();
    var savedAny = false;
    var noProgress = 0;
    final maxAttempts = (focusTopics.length + 1).clamp(3, 6);
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (shouldContinue != null && !shouldContinue()) {
        throw StateError(
          'Learning generation was cancelled because the administrator session changed.',
        );
      }
      try {
        final message = await _invokeAutomation(
          body: {'mode': 'manual', 'focus_topics': pending.toList()},
          failureMessage: 'Content automation could not be started.',
          allowNoNewContent: attempt == 0,
        );
        return attempt == 0
            ? message
            : 'Selected topics finished after waiting for the AI provider. Review the draft list. $message';
      } on _DeferredLearningGeneration catch (error) {
        savedAny = savedAny || error.hasSavedDrafts;
        noProgress = error.newDrafts > 0 ? 0 : noProgress + 1;
        final next = error.topics.toSet();
        if (attempt == maxAttempts - 1 ||
            noProgress >= 3 ||
            next.isEmpty ||
            !pending.containsAll(next)) {
          if (savedAny) throw PartialGenerationException(error.message);
          throw StateError(error.message);
        }
        pending = next;
        onProgress?.call(
          'AI provider is busy. Retrying ${pending.length} remaining topic(s) in ${error.retryAfterSeconds} seconds. Saved drafts are kept.',
        );
        await _wait(Duration(seconds: error.retryAfterSeconds));
        onProgress?.call('Generating ${pending.length} remaining topic(s)...');
      } on StateError catch (error) {
        if (savedAny && error is! PartialGenerationException) {
          throw PartialGenerationException(error.message);
        }
        rethrow;
      }
    }
    throw StateError('Learning generation could not finish.');
  }

  Future<String> runVerificationDraftsNow({
    List<VerificationSubskill> focusSkills = const [],
  }) async {
    return _invokeAutomation(
      body: {
        'mode': 'manual',
        'target': 'verification',
        if (focusSkills.isNotEmpty)
          'focus_skills': focusSkills.map((skill) => skill.id).toSet().toList(),
      },
      failureMessage: 'Verification draft generation could not be started.',
    );
  }

  Future<String> _invokeAutomation({
    required Map<String, dynamic> body,
    required String failureMessage,
    bool allowNoNewContent = true,
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
      if (body['target'] != 'verification' &&
          data['retryable'] == true &&
          data['pendingTopics'] is List &&
          data['retryAfterSeconds'] is num) {
        final seconds = (data['retryAfterSeconds'] as num).toInt();
        if (seconds > 0 && seconds <= 90) {
          throw _DeferredLearningGeneration(
            _responseMessage(data, failureMessage),
            (data['pendingTopics'] as List).whereType<String>().toList(),
            seconds,
            (data['draftsCreated'] is num && data['draftsCreated'] > 0) ||
                (data['existingDraftsAvailable'] is num &&
                    data['existingDraftsAvailable'] > 0),
            data['draftsCreated'] is num
                ? (data['draftsCreated'] as num).toInt()
                : 0,
          );
        }
      }
      // Partial runs saved real drafts; retain an explicit warning outcome.
      if (body['target'] != 'verification' &&
          data['noNewContent'] == true &&
          data['error'] == null &&
          data['draftsCreated'] == 0 &&
          allowNoNewContent) {
        return _responseMessage(
          data,
          'No new lesson draft was needed or available.',
        );
      }
      if (data['partial'] == true) {
        var message = _responseMessage(data, failureMessage);
        final saved = body['target'] == 'verification'
            ? data['verificationDraftsCreated']
            : data['draftsCreated'];
        if (message.contains('429') && saved is num && saved > 0) {
          message =
              '$saved drafts saved for review. The AI provider rate-limited the remaining requests. Review the saved drafts and retry remaining topics later.';
        }
        throw PartialGenerationException(message);
      }
      if (data['success'] == false || data['error'] != null) {
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
        .select()
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
