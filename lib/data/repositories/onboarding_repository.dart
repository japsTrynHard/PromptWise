import 'package:supabase_flutter/supabase_flutter.dart';

/// An account-scoped orientation record, not a measure of learner mastery.
class OrientationRecord {
  final DateTime? completedAt;
  final DateTime? videoWatchedAt;
  final DateTime? surveyCompletedAt;
  final bool surveyExempt;

  const OrientationRecord({
    this.completedAt, this.videoWatchedAt, this.surveyCompletedAt,
    this.surveyExempt = false,
  });

  bool get isComplete => completedAt != null;
  bool get videoWatched => videoWatchedAt != null;
  bool get surveyReady => surveyCompletedAt != null || surveyExempt;

  factory OrientationRecord.fromMap(Map<String, dynamic> data) {
    return OrientationRecord(
      completedAt: DateTime.tryParse(
        data['orientation_completed_at']?.toString() ?? '',
      ),
      videoWatchedAt: DateTime.tryParse(
        data['video_watched_at']?.toString() ?? '',
      ),
      surveyCompletedAt: DateTime.tryParse(
        data['survey_completed_at']?.toString() ?? '',
      ),
      surveyExempt: data['survey_exempt'] == true,
    );
  }
}

abstract interface class OnboardingGateway {
  Future<OrientationRecord?> fetch(String userId);
  Future<OrientationRecord> complete(String userId, {required bool watched});
}

class OnboardingRepository implements OnboardingGateway {
  final SupabaseClient _client;

  const OnboardingRepository(this._client);

  void _assertCurrentUser(String userId) {
    if (_client.auth.currentUser?.id != userId) {
      throw StateError('Orientation is available only for the signed-in account.');
    }
  }

  @override
  Future<OrientationRecord?> fetch(String userId) async {
    _assertCurrentUser(userId);
    final data = await _client
        .from('learner_onboarding')
        .select('orientation_completed_at,video_watched_at,survey_completed_at,survey_exempt')
        .eq('user_id', userId)
        .maybeSingle();
    if (data == null) return null;
    return OrientationRecord.fromMap(data);
  }

  @override
  Future<OrientationRecord> complete(
    String userId, {
    required bool watched,
  }) async {
    _assertCurrentUser(userId);
    // The SQL RPC uses auth.uid() and server time; the client cannot choose
    // another account or forge an arbitrary completion timestamp.
    final data = await _client.rpc(
      'complete_my_orientation',
      params: {'p_watched': watched},
    );
    if (data is! Map) {
      throw const FormatException('Orientation completion returned invalid data.');
    }
    // The original orientation RPC only returns video/orientation timestamps.
    // Re-fetch to retain survey completion/exemption instead of accidentally
    // sending an existing learner back through the survey gate on replay.
    return await fetch(userId) ??
        OrientationRecord.fromMap(Map<String, dynamic>.from(data));
  }
}
