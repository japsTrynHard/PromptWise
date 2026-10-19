import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:promptwise/data/services/awareness_feed_service.dart';
import 'package:promptwise/data/services/verification_media_service.dart';
import 'package:promptwise/data/repositories/verification_repository.dart';

void main() {
  for (final count in [0, 2, 5]) {
    test(
      'TC_IMAGE_POS_001/NEG_001 requires five distinct playable rounds ($count available)',
      () async {
        final client = await _client(
          (request) async => _json({
            'rounds': [for (var i = 0; i < count; i++) _round(i)],
          }),
        );
        final service = VerificationMediaService(client: client);
        if (count == 5) {
          expect(await service.fetchRounds(), hasLength(5));
        } else {
          expect(
            service.fetchRounds(),
            throwsA(isA<VerificationMediaException>()),
          );
        }
      },
    );
  }
  test(
    'TC_IMAGE_NEG_001 duplicated rounds cannot masquerade as a five-round set',
    () async {
      final client = await _client(
        (request) async => _json({'rounds': List.filled(5, _round(0))}),
      );
      expect(
        VerificationMediaService(client: client).fetchRounds(),
        throwsA(isA<VerificationMediaException>()),
      );
    },
  );

  for (final count in [0, 4, 5]) {
    test(
      'TC_VERIFY_POS_001/NEG_001 validates the five-case response ($count available)',
      () async {
        final client = await _client(
          (request) async => _json({
            'session_id': 'session',
            'cases': [
              for (var i = 0; i < count; i++)
                {
                  'case_id': 'c$i',
                  'title': 'Source check',
                  'scenario': 'Check the claim.',
                  'subskill': 'claim_verification',
                  'correct_decision': 'supported',
                  'explanation': 'The source supports this claim.',
                },
            ],
          }),
        );
        final request = VerificationRepository(
          client,
        ).createSession(caseCount: 5, rankLevel: 1);
        if (count == 5) {
          expect((await request).cases, hasLength(5));
        } else {
          expect(request, throwsStateError);
        }
      },
    );
  }

  test(
    'TC_AWARE_POS_001/003 and NEG_001 feed excludes unrelated stories and duplicate sources',
    () async {
      final client = await _client(
        (request) async => _json([
          _article('ai', 'AI deepfake warning', 'https://example.test/ai'),
          _article(
            'sports',
            'General sports results',
            'https://example.test/sports',
          ),
          _article('ai', 'AI deepfake warning', 'https://example.test/ai'),
          _article(
            'duplicate',
            'AI deepfake warning',
            'https://example.test/ai',
          ),
          _article('bad-url', 'AI deepfake warning', 'javascript:alert(1)'),
        ]),
      );
      final service = AwarenessFeedService(client: client);
      addTearDown(service.dispose);
      final articles = await service.fetchFeed(refreshIfStale: false);
      expect(articles.map((a) => a.id), ['ai']);
      expect(articles.single.sourceUrl, 'https://example.test/ai');
    },
  );

  for (final body in [
    'not json',
    '{}',
    '{"success":false,"error":"Provider unavailable"}',
    '{"success":false,"warning":"Provider unavailable","activeCount":10}',
  ]) {
    test(
      'TC_AWARE_NEG_003 malformed or failed update cannot claim success: $body',
      () async {
        final client = await _client((_) async => _json([]));
        final service = AwarenessFeedService(
          client: client,
          httpClient: MockClient((_) async => http.Response(body, 200)),
        );
        addTearDown(service.dispose);
        expect(
          service.checkForUpdates(),
          throwsA(isA<AwarenessFeedException>()),
        );
      },
    );
  }
}

Map<String, dynamic> _round(int i) => {
  'id': 'r$i',
  'question': 'Which image is AI-made?',
  'image_a': {'id': 'r${i}a', 'image_url': 'https://example.test/${i}a.jpg'},
  'image_b': {'id': 'r${i}b', 'image_url': 'https://example.test/${i}b.jpg'},
};
Map<String, dynamic> _article(String id, String title, String url) => {
  'id': id,
  'title': title,
  'source_url': url,
};
http.Response _json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);

Future<SupabaseClient> _client(
  Future<http.Response> Function(http.Request) handler,
) async {
  final client = SupabaseClient(
    'https://example.test',
    'test-key',
    httpClient: MockClient((request) async {
      final response = await handler(request);
      return http.Response.bytes(
        response.bodyBytes,
        response.statusCode,
        headers: response.headers,
        request: request,
      );
    }),
  );
  addTearDown(client.dispose);
  final expiry =
      DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/
      1000;
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'exp': expiry, 'sub': 'learner'})))
      .replaceAll('=', '');
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.test',
      'refresh_token': 'test-refresh',
      'token_type': 'bearer',
      'expires_in': 86400,
      'expires_at': expiry,
      'user': {
        'id': 'learner',
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    }),
  );
  return client;
}
