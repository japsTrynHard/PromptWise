import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/dictionary_entry.dart';

class DictionaryService {
  DictionaryService({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;

  Future<DictionaryEntry> lookup(String word) async {
    final cleaned = word.trim().toLowerCase();
    final uri = Uri.parse(
      'https://api.dictionaryapi.dev/api/v2/entries/en/${Uri.encodeComponent(cleaned)}',
    );

    final response = await _http
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 12));

    if (response.statusCode == 404) {
      throw const DictionaryNotFoundException();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const DictionaryServiceException(
        'The dictionary is temporarily unavailable. Please try again.',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const DictionaryServiceException(
        'The dictionary returned an unreadable response. Please try again.',
      );
    }

    if (decoded is! List || decoded.isEmpty || decoded.first is! Map) {
      throw const DictionaryServiceException(
        'No readable definition was returned for this word.',
      );
    }

    final entry = DictionaryEntry.fromApiMap(
      Map<String, dynamic>.from(decoded.first as Map),
    );
    if (entry.definitions.isEmpty) {
      throw const DictionaryServiceException(
        'No readable definition was returned for this word.',
      );
    }
    return entry;
  }

  void dispose() {
    _http.close();
  }
}

class DictionaryServiceException implements Exception {
  final String message;
  const DictionaryServiceException(this.message);

  @override
  String toString() => message;
}

class DictionaryNotFoundException extends DictionaryServiceException {
  const DictionaryNotFoundException()
    : super('No definition was found. Try another word from the lesson.');
}
