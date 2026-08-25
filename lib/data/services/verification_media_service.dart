import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_environment.dart';
import '../models/image_comparison.dart';

class VerificationMediaService {
  VerificationMediaService({
    required SupabaseClient client,
    http.Client? httpClient,
  })  : _client = client,
        _http = httpClient ?? http.Client();

  final SupabaseClient _client;
  final http.Client _http;

  Future<List<ImageComparisonRound>> fetchRounds({
    int count = 5,
    Set<String> seenIds = const {},
  }) async {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw const VerificationMediaException('Please sign in again to continue.');
    }

    final uri = Uri.parse(
      '${AppEnvironment.supabaseUrl}/functions/v1/verification-media',
    );
    final response = await _http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'apikey': AppEnvironment.supabasePublishableKey,
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'count': count.clamp(3, 8),
            'seen_ids': seenIds.take(60).toList(growable: false),
          }),
        )
        .timeout(const Duration(seconds: 25));

    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException();
      body = Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw const VerificationMediaException(
        'Image examples could not be loaded right now.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = body['message']?.toString().trim();
      throw VerificationMediaException(
        message?.isNotEmpty == true
            ? message!
            : 'Fresh image examples are temporarily unavailable.',
      );
    }

    final rawRounds = body['rounds'];
    if (rawRounds is! List) {
      throw const VerificationMediaException(
        'Fresh image examples are temporarily unavailable.',
      );
    }

    final rounds = <ImageComparisonRound>[];
    for (final raw in rawRounds) {
      if (raw is! Map) continue;
      try {
        rounds.add(
          ImageComparisonRound.fromMap(Map<String, dynamic>.from(raw)),
        );
      } on FormatException {
        // Skip one malformed online item without breaking the whole activity.
      }
    }

    if (rounds.length < 2) {
      throw const VerificationMediaException(
        'Not enough fresh image examples were available. Try again in a moment.',
      );
    }
    return List.unmodifiable(rounds);
  }

  void dispose() => _http.close();
}

class VerificationMediaException implements Exception {
  final String message;
  const VerificationMediaException(this.message);

  @override
  String toString() => message;
}
