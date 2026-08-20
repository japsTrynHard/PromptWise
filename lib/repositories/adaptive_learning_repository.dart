import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/adaptive_learning.dart';
import '../models/learning_topic.dart';

class AdaptiveLearningRepository {
  final SupabaseClient _client;

  const AdaptiveLearningRepository(this._client);

  Future<List<TopicMastery>> fetchTopicMastery(String userId) async {
    final response = await _client
        .from('topic_mastery')
        .select()
        .eq('user_id', userId)
        .order('topic_id');
    return (response as List)
        .map(
          (row) => TopicMastery.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<List<DiagnosticAttemptRecord>> fetchDiagnosticAttempts(
    String userId,
  ) async {
    final response = await _client
        .from('assessment_attempts')
        .select('answers, completed_at')
        .eq('user_id', userId)
        .eq('assessment_type', 'diagnostic')
        .order('completed_at');

    return (response as List)
        .map(
          (row) => DiagnosticAttemptRecord.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<List<AdaptiveQuestionAttemptRecord>> fetchQuestionAttempts(
    String userId, {
    bool countedOnly = false,
  }) async {
    final baseQuery = _client
        .from('question_attempts')
        .select(
          'item_id, topic_id, is_correct, attempt_type, counted_for_mastery, attempted_at',
        )
        .eq('user_id', userId);
    final response = countedOnly
        ? await baseQuery.eq('counted_for_mastery', true).order('attempted_at')
        : await baseQuery.order('attempted_at');

    final records = <AdaptiveQuestionAttemptRecord>[];
    for (final row in response as List) {
      try {
        records.add(
          AdaptiveQuestionAttemptRecord.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        );
      } on FormatException {
        // Ignore malformed legacy rows rather than breaking adaptive loading.
      }
    }
    return records;
  }

  Future<bool> hasDiagnosticAssessment(String userId) async {
    final response = await _client
        .from('assessment_attempts')
        .select('id')
        .eq('user_id', userId)
        .eq('assessment_type', 'diagnostic')
        .limit(1);
    return (response as List).isNotEmpty;
  }

  /// Server-authoritative attempt recording. The Phase 6 final migration
  /// decides atomically whether an attempt is eligible to change mastery.
  Future<bool> recordQuestionAttempt({
    required String userId,
    required String itemId,
    required LearningTopic topic,
    required bool isCorrect,
    required String attemptType,
    required bool countedForMastery,
    DateTime? attemptedAt,
  }) async {
    final occurredAt = (attemptedAt ?? DateTime.now()).toUtc();
    try {
      final response = await _client.rpc(
        'record_adaptive_attempt',
        params: {
          'p_user_id': userId,
          'p_item_id': itemId,
          'p_topic_id': topic.id,
          'p_is_correct': isCorrect,
          'p_attempt_type': attemptType,
          'p_counted_for_mastery': countedForMastery,
          'p_attempted_at': occurredAt.toIso8601String(),
        },
      );
      return _asBool(response);
    } on PostgrestException catch (error) {
      if (!_isMissingRpc(error)) rethrow;
      return _legacyInsertAttempt(
        userId: userId,
        itemId: itemId,
        topic: topic,
        isCorrect: isCorrect,
        attemptType: attemptType,
        countedForMastery: countedForMastery,
        attemptedAt: occurredAt,
      );
    }
  }

  Future<bool> _legacyInsertAttempt({
    required String userId,
    required String itemId,
    required LearningTopic topic,
    required bool isCorrect,
    required String attemptType,
    required bool countedForMastery,
    required DateTime attemptedAt,
  }) async {
    final row = <String, dynamic>{
      'user_id': userId,
      'item_id': itemId,
      'topic_id': topic.id,
      'is_correct': isCorrect,
      'attempt_type': attemptType,
      'counted_for_mastery': countedForMastery,
      'attempted_at': attemptedAt.toIso8601String(),
      'attempt_day': philippinesDayKey(attemptedAt),
    };
    try {
      await _client.from('question_attempts').insert(row);
      return countedForMastery;
    } on PostgrestException catch (error) {
      if (countedForMastery && error.code == '23505') {
        row['counted_for_mastery'] = false;
        await _client.from('question_attempts').insert(row);
        return false;
      }
      rethrow;
    }
  }

  Future<bool> recordDiagnosticAttempt({
    required String userId,
    required DiagnosticResult result,
    required Map<String, int> answers,
    DateTime? completedAt,
  }) async {
    final occurredAt = (completedAt ?? DateTime.now()).toUtc();
    try {
      final response = await _client.rpc(
        'record_adaptive_diagnostic',
        params: {
          'p_user_id': userId,
          'p_score': result.score,
          'p_correct_answers': result.correctAnswers,
          'p_total_questions': result.totalQuestions,
          'p_answers': answers,
          'p_completed_at': occurredAt.toIso8601String(),
        },
      );
      return _asBool(response);
    } on PostgrestException catch (error) {
      if (!_isMissingRpc(error)) rethrow;
      try {
        await _client.from('assessment_attempts').insert({
          'user_id': userId,
          'assessment_type': 'diagnostic',
          'score': result.score,
          'correct_answers': result.correctAnswers,
          'total_questions': result.totalQuestions,
          'answers': answers,
          'completed_at': occurredAt.toIso8601String(),
        });
        return true;
      } on PostgrestException catch (insertError) {
        if (insertError.code == '23505') return false;
        rethrow;
      }
    }
  }

  Future<void> rebuildAdaptiveMastery(String userId) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId != userId) {
      throw StateError('Adaptive mastery can only be rebuilt for the signed-in learner.');
    }
    try {
      await _client.rpc('rebuild_my_adaptive_mastery');
    } on PostgrestException catch (error) {
      // Older databases do not have the final hardening RPC. History replay in
      // the controller still keeps the UI correct until the migration is run.
      if (!_isMissingRpc(error)) rethrow;
    }
  }

  // Kept for compatibility with older callers. Final Phase 6 writes aggregates
  // through the database rebuild function instead of trusting client values.
  Future<void> upsertTopicMastery({
    required String userId,
    required TopicMastery mastery,
  }) async {
    await _client.from('topic_mastery').upsert(
      mastery.toMap(userId: userId),
      onConflict: 'user_id,topic_id',
    );
  }

  Future<void> upsertReviewSchedule({
    required String userId,
    required TopicMastery mastery,
  }) async {
    final dueAt = mastery.nextReviewAt;
    if (dueAt == null) return;
    await _client.from('review_schedule').upsert({
      'user_id': userId,
      'topic_id': mastery.topic.id,
      'due_at': dueAt.toUtc().toIso8601String(),
      'mastery_snapshot': mastery.mastery,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,topic_id');
  }

  bool _asBool(dynamic response) {
    if (response is bool) return response;
    if (response is num) return response != 0;
    if (response is String) return response.toLowerCase() == 'true';
    if (response is List && response.isNotEmpty) return _asBool(response.first);
    if (response is Map && response.isNotEmpty) return _asBool(response.values.first);
    return false;
  }

  bool _isMissingRpc(PostgrestException error) {
    final code = (error.code ?? '').toUpperCase();
    final message = error.message.toLowerCase();
    return code == 'PGRST202' ||
        code == '42883' ||
        message.contains('function') && message.contains('does not exist');
  }
}
