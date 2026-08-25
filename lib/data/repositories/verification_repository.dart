import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/verification.dart';

class VerificationRepository {
  final SupabaseClient _client;

  const VerificationRepository(this._client);

  Future<List<VerificationSubskillMastery>> fetchSubskillMastery() async {
    final response = await _client
        .from('verification_subskill_mastery')
        .select('subskill,mastery,attempts,successful_attempts,last_practiced_at,next_review_at')
        .order('subskill');
    final result = <VerificationSubskillMastery>[];
    for (final row in response as List) {
      try {
        result.add(
          VerificationSubskillMastery.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        );
      } on FormatException {
        // Keep the learner page usable if an old malformed row exists.
      }
    }
    return result;
  }

  Future<VerificationSession> createSession({
    required int caseCount,
    required int rankLevel,
  }) async {
    final response = await _client.rpc(
      'create_adaptive_verification_session',
      params: {
        'p_case_count': caseCount.clamp(4, 10),
        'p_rank_level': rankLevel.clamp(1, 5),
      },
    );
    final session = VerificationSession.fromMap(_jsonMap(response));
    if (session.id.isEmpty || session.cases.isEmpty) {
      throw StateError('No eligible verification cases are available right now.');
    }
    return session;
  }

  Future<VerificationCaseFeedback> submitGuess({
    required String sessionId,
    required String caseId,
    required VerificationDecision decision,
  }) async {
    final response = await _client.rpc(
      'submit_verification_guess',
      params: {
        'p_session_id': sessionId,
        'p_case_id': caseId,
        'p_decision': decision.id,
      },
    );
    return VerificationCaseFeedback.fromMap(_jsonMap(response));
  }

  Future<VerificationSessionSummary> completeSession(String sessionId) async {
    final response = await _client.rpc(
      'complete_verification_session',
      params: {'p_session_id': sessionId},
    );
    return VerificationSessionSummary.fromMap(_jsonMap(response));
  }

  Future<void> abandonSession(String sessionId) async {
    await _client.rpc(
      'abandon_verification_session',
      params: {'p_session_id': sessionId},
    );
  }

  Future<List<VerificationCaseDraft>> fetchDrafts() async {
    final response = await _client
        .from('verification_case_drafts')
        .select('id,title,summary,draft_payload,source_name,source_url,source_published_at,created_at,status')
        .eq('status', 'draft')
        .order('created_at', ascending: false)
        .limit(100);
    final result = <VerificationCaseDraft>[];
    for (final row in response as List) {
      try {
        result.add(
          VerificationCaseDraft.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        );
      } on FormatException {
        // Ignore malformed AI drafts instead of breaking admin access.
      }
    }
    return result;
  }

  Future<List<VerificationCaseHealth>> fetchHealth() async {
    final response = await _client
        .from('phase9_verification_case_health')
        .select()
        .order('subskill');
    final result = <VerificationCaseHealth>[];
    for (final row in response as List) {
      try {
        result.add(
          VerificationCaseHealth.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        );
      } on FormatException {
        // Ignore malformed aggregate rows.
      }
    }
    return result;
  }

  Future<List<VerificationCase>> fetchPublishedCases() async {
    final response = await _client.rpc('admin_list_verification_cases');
    final rows = response is List ? response : const [];
    final result = <VerificationCase>[];
    for (final row in rows) {
      if (row is! Map) continue;
      try {
        result.add(
          VerificationCase.fromMap(Map<String, dynamic>.from(row)),
        );
      } on FormatException {
        // Ignore malformed cases so the rest of the bank remains manageable.
      }
    }
    return result;
  }

  Future<VerificationAutomationOverview> fetchAutomationOverview() async {
    final response = await _client.rpc('get_verification_automation_overview');
    return VerificationAutomationOverview.fromMap(_jsonMap(response));
  }

  Future<void> updateAutomationSettings({
    required bool enabled,
    required int maxArticlesPerRun,
    required int maxDraftsPerRun,
    required int maxDraftsPerDay,
    required int monthlyDraftCap,
    required int monthlyGroqRequestCap,
    required int maxPendingDrafts,
    required int manualCooldownMinutes,
  }) async {
    await _client.rpc(
      'update_verification_automation_settings',
      params: {
        'p_enabled': enabled,
        'p_max_articles_per_run': maxArticlesPerRun,
        'p_max_drafts_per_run': maxDraftsPerRun,
        'p_max_drafts_per_day': maxDraftsPerDay,
        'p_monthly_draft_cap': monthlyDraftCap,
        'p_monthly_groq_request_cap': monthlyGroqRequestCap,
        'p_max_pending_drafts': maxPendingDrafts,
        'p_manual_cooldown_minutes': manualCooldownMinutes,
      },
    );
  }

  Future<void> approveDraft(String draftId) async {
    await _client.rpc(
      'approve_verification_case_draft',
      params: {'p_draft_id': draftId},
    );
  }

  Future<void> rejectDraft(String draftId) async {
    await _client.rpc(
      'reject_verification_case_draft',
      params: {'p_draft_id': draftId},
    );
  }

  Future<void> updateCase({
    required String caseId,
    required String title,
    required String scenario,
    required String claimText,
    required VerificationSubskill subskill,
    required VerificationCaseType caseType,
    required int difficulty,
    required VerificationDecision correctDecision,
    required VerificationConfidence expectedConfidence,
    required String explanation,
    required String learningPoint,
  }) async {
    await _client.rpc(
      'update_verification_case_core',
      params: {
        'p_case_id': caseId,
        'p_title': title.trim(),
        'p_scenario': scenario.trim(),
        'p_claim_text': claimText.trim(),
        'p_subskill': subskill.id,
        'p_case_type': caseType.id,
        'p_difficulty': difficulty.clamp(1, 5),
        'p_correct_decision': correctDecision.id,
        'p_expected_confidence': expectedConfidence.id,
        'p_explanation': explanation.trim(),
        'p_learning_point': learningPoint.trim(),
      },
    );
  }

  Future<void> archiveCase(String caseId) async {
    await _client.rpc(
      'archive_verification_case',
      params: {'p_case_id': caseId},
    );
  }

  Map<String, dynamic> _jsonMap(dynamic response) {
    if (response is Map) return Map<String, dynamic>.from(response);
    if (response is List && response.isNotEmpty && response.first is Map) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    throw const FormatException('Unexpected verification server response.');
  }
}
