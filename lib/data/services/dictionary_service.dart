import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/dictionary_entry.dart';

abstract interface class DictionaryLookupService {
  Future<DictionaryEntry> lookup(String word);
}

class DictionaryService implements DictionaryLookupService {
  DictionaryService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<DictionaryEntry> lookup(String word) async {
    final cleaned = word.trim().toLowerCase();
    if (cleaned.isEmpty || cleaned.length > 50) {
      throw const DictionaryServiceException(
        'Enter one short word from the lesson.',
        kind: DictionaryFailureKind.invalidRequest,
      );
    }

    late final FunctionResponse response;
    try {
      response = await _client.functions
          .invoke('dictionary-lookup', body: {'word': cleaned})
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw const DictionaryServiceException(
        'The connection is taking too long. Please try again.',
        kind: DictionaryFailureKind.timeout,
      );
    } on FunctionException catch (error) {
      _throwFunctionFailure(error.status, error.details);
    }
    final data = response.data;
    final body = data is Map
        ? Map<String, dynamic>.from(data)
        : const <String, dynamic>{};

    final rawEntry = body['entry'];
    if (rawEntry is! Map) {
      throw const DictionaryServiceException(
        'The dictionary returned an unreadable response. Please try again.',
        kind: DictionaryFailureKind.invalidResponse,
      );
    }
    final entry = DictionaryEntry.fromMap(Map<String, dynamic>.from(rawEntry));
    if (entry.word.isEmpty || entry.definitions.isEmpty) {
      throw const DictionaryServiceException(
        'No readable definition was returned for this word.',
        kind: DictionaryFailureKind.invalidResponse,
      );
    }
    return entry;
  }

  Never _throwFunctionFailure(int status, dynamic details) {
    final body = details is Map
        ? Map<String, dynamic>.from(details)
        : const <String, dynamic>{};
    final code = body['code']?.toString().trim().toLowerCase();
    final message = body['message']?.toString().trim();
    if (status == 404 || code == 'not_found') {
      throw const DictionaryNotFoundException();
    }
    if (status == 401 || status == 403) {
      throw const DictionaryServiceException(
        'Please sign in again to use the lesson dictionary.',
        kind: DictionaryFailureKind.authentication,
      );
    }
    if (status == 429 || code == 'rate_limited') {
      throw const DictionaryServiceException(
        'The dictionary is busy right now. Wait a moment, then try again.',
        kind: DictionaryFailureKind.rateLimited,
      );
    }
    if (status == 504 || code == 'timeout') {
      throw const DictionaryServiceException(
        'The dictionary lookup took too long. Please try again.',
        kind: DictionaryFailureKind.timeout,
      );
    }
    if (code == 'network_failure') {
      throw const DictionaryServiceException(
        'The dictionary providers could not be reached. Please try again.',
        kind: DictionaryFailureKind.network,
      );
    }
    if (code == 'malformed_response' || code == 'invalid_response') {
      throw const DictionaryServiceException(
        'The dictionary providers returned unreadable results. Please try again.',
        kind: DictionaryFailureKind.invalidResponse,
      );
    }
    if (status == 400 || code == 'invalid_request') {
      throw DictionaryServiceException(
        message?.isNotEmpty == true
            ? message!
            : 'Enter one short word from the lesson.',
        kind: DictionaryFailureKind.invalidRequest,
      );
    }
    throw DictionaryServiceException(
      message?.isNotEmpty == true
          ? message!
          : 'The dictionary is temporarily unavailable. Please try again.',
      kind: code == 'server_error'
          ? DictionaryFailureKind.unknown
          : DictionaryFailureKind.upstream,
    );
  }
}

enum DictionaryFailureKind {
  invalidRequest,
  authentication,
  notFound,
  rateLimited,
  timeout,
  network,
  upstream,
  invalidResponse,
  unknown,
}

class DictionaryServiceException implements Exception {
  final String message;
  final DictionaryFailureKind kind;

  const DictionaryServiceException(
    this.message, {
    this.kind = DictionaryFailureKind.unknown,
  });

  @override
  String toString() => message;
}

class DictionaryNotFoundException extends DictionaryServiceException {
  const DictionaryNotFoundException()
    : super(
        'No definition was found. Try another word from the lesson.',
        kind: DictionaryFailureKind.notFound,
      );
}
