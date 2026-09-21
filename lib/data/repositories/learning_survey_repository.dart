import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/learning_survey.dart';
import '../models/learning_topic.dart';

abstract interface class LearningSurveyGateway {
  Future<LearningSurvey?> fetch(String userId);
  Future<LearningSurvey> save(String userId, LearningSurvey survey);
}

class LearningSurveyRepository implements LearningSurveyGateway {
  final SupabaseClient _client;
  const LearningSurveyRepository(this._client);

  void _assertOwnAccount(String userId) {
    if (_client.auth.currentUser?.id != userId) {
      throw StateError('Sign in to your own account before editing the survey.');
    }
  }

  @override
  Future<LearningSurvey?> fetch(String userId) async {
    _assertOwnAccount(userId);
    final data = await _client.from('learner_survey')
        .select('interests,experience_level,learning_goal,updated_at')
        .eq('user_id', userId).maybeSingle();
    return data == null ? null : LearningSurvey.fromMap(data);
  }

  @override
  Future<LearningSurvey> save(String userId, LearningSurvey survey) async {
    _assertOwnAccount(userId);
    survey.validate();
    final data = await _client.rpc('save_my_learning_survey', params: {
      'p_interests': survey.interests.map((topic) => topic.id).toList(),
      'p_experience_level': survey.experienceLevel,
      'p_learning_goal': survey.learningGoal,
    });
    if (data is! Map) {
      throw const FormatException('Survey save returned invalid data.');
    }
    return LearningSurvey.fromMap(Map<String, dynamic>.from(data));
  }
}
