import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_environment.dart';
import '../models/prompt_coach.dart';

class IntegrationService {
  IntegrationService({required SupabaseClient client, http.Client? httpClient})
    : _client = client,
      _http = httpClient ?? http.Client();

  final SupabaseClient _client;
  final http.Client _http;

  Future<PromptCoachServiceStatus> getCoachStatus() async {
    final response = await _http
        .get(_functionUri(method: 'coach-status'), headers: _headers())
        .timeout(const Duration(seconds: 15));
    final body = _decodeObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw IntegrationException(_messageFrom(body));
    }
    return PromptCoachServiceStatus.fromMap(body);
  }

  Future<PromptAiGuidanceResult> getPromptGuidance({
    required String prompt,
    required PromptCoachAnalysis standardAnalysis,
    required Map<String, int> masteryContext,
    required String learnerRank,
  }) async {
    final response = await _http
        .post(
          _functionUri(method: 'coach'),
          headers: {..._headers(), 'Content-Type': 'application/json'},
          body: jsonEncode({
            'prompt': prompt.trim(),
            'standard_analysis': standardAnalysis.toMap(),
            'mastery_context': masteryContext,
            'learner_rank': learnerRank,
          }),
        )
        .timeout(const Duration(seconds: 35));
    final body = _decodeObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw IntegrationException(_messageFrom(body));
    }

    final rawGuidance = body['guidance'];
    if (rawGuidance is! Map) {
      throw const IntegrationException(
        'The AI Coach returned an unreadable response.',
      );
    }
    final rawUsage = body['usage'];
    return PromptAiGuidanceResult(
      guidance: PromptAiGuidance.fromMap(
        Map<String, dynamic>.from(rawGuidance),
      ),
      usage: rawUsage is Map
          ? PromptCoachUsage.fromMap(Map<String, dynamic>.from(rawUsage))
          : PromptCoachUsage.initial(),
    );
  }

  Uri _functionUri({required String method}) {
    final base = Uri.parse(
      '${AppEnvironment.supabaseUrl}/functions/v1/promptwise-integrations',
    );
    return base.replace(queryParameters: {'method': method});
  }

  Map<String, String> _headers() {
    final sessionToken = _client.auth.currentSession?.accessToken;
    if (sessionToken == null || sessionToken.isEmpty) {
      throw const IntegrationException('Please sign in again to continue.');
    }
    return {
      'Authorization': 'Bearer $sessionToken',
      'apikey': AppEnvironment.supabasePublishableKey,
      'Accept': 'application/json',
    };
  }

  Map<String, dynamic> _decodeObject(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // Converted to a user-friendly error below.
    }
    throw const IntegrationException(
      'The AI Coach returned an unreadable response.',
    );
  }

  String _messageFrom(Map<String, dynamic> body) {
    final message = body['message']?.toString().trim();
    if (message != null && message.isNotEmpty) return message;
    return 'AI guidance is temporarily unavailable. Please try again.';
  }

  void dispose() {
    _http.close();
  }
}

class IntegrationException implements Exception {
  final String message;
  const IntegrationException(this.message);

  @override
  String toString() => message;
}
