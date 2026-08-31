import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/image_comparison.dart';

abstract interface class VerificationMediaGateway {
  Future<List<ImageComparisonRound>> fetchRounds({
    int count = 5,
    Set<String> seenIds = const {},
  });

  Future<ImageComparisonAttemptResult> submitAttempt({
    required String roundId,
    required String selectedSide,
  });
}

class VerificationMediaService implements VerificationMediaGateway {
  VerificationMediaService({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  @override
  Future<List<ImageComparisonRound>> fetchRounds({
    int count = 5,
    Set<String> seenIds = const {},
  }) async {
    if (_client.auth.currentUser == null) {
      throw const VerificationMediaException(
        'Please sign in again to continue.',
      );
    }

    late final FunctionResponse response;
    try {
      response = await _client.functions
          .invoke(
            'verification-media',
            body: {
              'count': count.clamp(3, 8),
              'seen_ids': seenIds.take(60).toList(growable: false),
            },
          )
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw const VerificationMediaException(
        'Image examples are taking too long to load. Please try again.',
      );
    } on FunctionException catch (error) {
      throw VerificationMediaException(
        _functionErrorMessage(error.details),
      );
    }

    final data = response.data;
    if (data is! Map) {
      throw const VerificationMediaException(
        'Image examples could not be loaded right now.',
      );
    }
    final body = Map<String, dynamic>.from(data);

    if (response.status < 200 || response.status >= 300) {
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

  @override
  Future<ImageComparisonAttemptResult> submitAttempt({
    required String roundId,
    required String selectedSide,
  }) async {
    final response = await _client
        .rpc(
          'submit_image_comparison_attempt',
          params: {
            'p_round_id': roundId.trim(),
            'p_selected_side': selectedSide.trim().toUpperCase(),
          },
        )
        .timeout(const Duration(seconds: 15));
    if (response is Map) {
      final result = ImageComparisonAttemptResult.fromMap(
        Map<String, dynamic>.from(response),
      );
      if (result.roundId != roundId.trim()) {
        throw const VerificationMediaException(
          'The image feedback did not match the selected round.',
        );
      }
      return result;
    }
    if (response is List && response.isNotEmpty && response.first is Map) {
      final result = ImageComparisonAttemptResult.fromMap(
        Map<String, dynamic>.from(response.first as Map),
      );
      if (result.roundId != roundId.trim()) {
        throw const VerificationMediaException(
          'The image feedback did not match the selected round.',
        );
      }
      return result;
    }
    throw const VerificationMediaException(
      'Your answer could not be recorded right now.',
    );
  }

  void dispose() {}
}

String _functionErrorMessage(dynamic details) {
  if (details is Map) {
    final message = details['message']?.toString().trim();
    if (message?.isNotEmpty == true) return message!;
  }
  return 'Fresh image examples are temporarily unavailable.';
}

class VerificationMediaException implements Exception {
  final String message;
  const VerificationMediaException(this.message);

  @override
  String toString() => message;
}
