import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_progress.dart';

class ProgressRepository {
  final SupabaseClient client;

  const ProgressRepository(this.client);

  Future<UserProgress?> fetchProgress({
    required String userId,
    required int totalLessons,
  }) async {
    final data = await client
        .from('learner_progress')
        .select(
          'completed_lesson_ids, quiz_best_scores, badges, knowledge_level, updated_at',
        )
        .eq('user_id', userId)
        .maybeSingle();

    if (data == null) return null;

    final completed = (data['completed_lesson_ids'] as List? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);
    final badges = (data['badges'] as List? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);
    final rawScores = data['quiz_best_scores'];
    final scores = <String, int>{};
    if (rawScores is Map) {
      for (final entry in rawScores.entries) {
        final value = entry.value;
        if (value is num) scores[entry.key.toString()] = value.toInt();
      }
    }

    return UserProgress(
      completedLessonIds: completed,
      totalLessons: totalLessons,
      quizBestScores: scores,
      badges: badges,
      knowledgeLevel: data['knowledge_level'] as String? ?? 'Beginner',
    );
  }

  Future<void> upsertProgress({
    required String userId,
    required UserProgress progress,
  }) async {
    await client.from('learner_progress').upsert({
      'user_id': userId,
      'completed_lesson_ids': progress.completedLessonIds,
      'quiz_best_scores': progress.quizBestScores,
      'badges': progress.badges,
      'knowledge_level': progress.knowledgeLevel,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
  }
}
