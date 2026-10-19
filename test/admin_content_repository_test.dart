import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:promptwise/data/models/learning_topic.dart';
import 'package:promptwise/data/models/verification.dart';
import 'package:promptwise/data/repositories/content_automation_repository.dart';
import 'package:promptwise/data/repositories/content_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  SupabaseClient clientFor(
    Future<http.Response> Function(http.Request) handler,
  ) {
    final client = SupabaseClient(
      'https://example.invalid',
      'test-key',
      httpClient: MockClient((request) async {
        final response = await handler(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
          reasonPhrase: response.reasonPhrase,
        );
      }),
    );
    addTearDown(client.dispose);
    return client;
  }

  http.Response jsonResponse(Object value, int status) => http.Response(
    jsonEncode(value),
    status,
    headers: {'content-type': 'application/json'},
  );

  test('Learning saves a zero cooldown without coercing it', () async {
    final client = clientFor((request) async {
      expect(request.method, 'PATCH');
      expect(jsonDecode(request.body)['manual_cooldown_minutes'], 0);
      return jsonResponse({'id': 1}, 200);
    });
    await ContentAutomationRepository(client).updateSettings(
      manualCooldownMinutes: 0,
      enabled: true,
      maxArticlesPerRun: 2,
      maxDraftsPerDay: 3,
      monthlyDraftCap: 30,
      maxPendingDrafts: 10,
      maxPendingQuestions: 40,
      draftArchiveDays: 15,
      focusTopics: [LearningTopic.context],
    );
  });

  test(
    'approved bank reads approval metadata without requiring a new column on older servers',
    () async {
      final approvedAt = DateTime.utc(2026, 10, 19, 10, 20);
      final client = clientFor((request) async {
        expect(request.url.queryParameters['select'], '*');
        expect(request.url.queryParameters['validation_status'], 'eq.verified');
        return jsonResponse([
          {
            'id': 'q1',
            'topic_id': 'context',
            'approved_at': approvedAt.toIso8601String(),
          },
          {
            'id': 'q2',
            'topic_id': 'context',
            'created_at': '2020-01-01T00:00:00Z',
          },
        ], 200);
      });
      final rows = await ContentAutomationRepository(
        client,
      ).fetchApprovedQuestions();
      expect(rows.first.approvedAt, approvedAt);
      expect(
        rows.first.copyWith(stem: 'Edited question').approvedAt,
        approvedAt,
      );
      expect(rows.last.approvedAt, isNull);
      final legacyCase = VerificationCase.fromMap({
        'id': 'c1',
        'subskill': 'claim_verification',
        'correct_decision': 'supported',
        'created_at': '2020-01-01T00:00:00Z',
      });
      expect(legacyCase.approvedAt, isNull);
    },
  );

  for (final topic in LearningTopic.values) {
    test('manual selection forwards only ${topic.id}', () async {
      final client = clientFor((request) async {
        expect(jsonDecode(request.body)['focus_topics'], [topic.id]);
        return jsonResponse({'message': 'Draft queued.'}, 200);
      });
      await ContentAutomationRepository(client).runAutomationNow([topic]);
    });
  }

  for (final skill in VerificationSubskill.values) {
    test('Verify selection forwards only ${skill.id}', () async {
      final client = clientFor((request) async {
        expect(jsonDecode(request.body), {
          'mode': 'manual',
          'target': 'verification',
          'focus_skills': [skill.id],
        });
        return jsonResponse({'message': 'Draft queued.'}, 200);
      });
      await ContentAutomationRepository(
        client,
      ).runVerificationDraftsNow(focusSkills: [skill]);
    });
  }

  test(
    'manual generation sends the selected topics and returns the server result',
    () async {
      final client = clientFor((request) async {
        expect(request.url.path, '/functions/v1/content-automation');
        expect(jsonDecode(request.body), {
          'mode': 'manual',
          'focus_topics': ['context'],
        });
        return jsonResponse({
          'success': true,
          'message': 'One draft created.',
        }, 200);
      });
      expect(
        await ContentAutomationRepository(
          client,
        ).runAutomationNow([LearningTopic.context]),
        'One draft created.',
      );
    },
  );

  for (final entry in {
    429: 'Please try again in about 12 minutes.',
    500: 'GROQ_API_KEY is not configured.',
    403: 'Administrator access required.',
  }.entries) {
    test('HTTP ${entry.key} preserves the actionable backend error', () async {
      final client = clientFor(
        (_) async => jsonResponse({'error': entry.value}, entry.key),
      );
      expect(
        ContentAutomationRepository(
          client,
        ).runAutomationNow([LearningTopic.context]),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', entry.value),
        ),
      );
    });
  }

  test('partial generation is not reported as complete success', () async {
    final client = clientFor(
      (_) async => jsonResponse({
        'partial': true,
        'success': false,
        'message': 'One draft saved, one source failed.',
      }, 200),
    );
    expect(
      ContentAutomationRepository(
        client,
      ).runAutomationNow([LearningTopic.context]),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('One draft saved'),
        ),
      ),
    );
  });

  test(
    'non-JSON success response cannot report a successful generation',
    () async {
      final client = clientFor(
        (_) async => http.Response('Proxy response', 200),
      );
      expect(
        ContentAutomationRepository(
          client,
        ).runAutomationNow([LearningTopic.context]),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'source toggle detects zero updated rows instead of reporting success',
    () async {
      final client = clientFor((request) async {
        expect(request.url.queryParameters['id'], 'eq.source-1');
        expect(request.url.queryParameters['select'], 'id');
        expect(
          request.headers['Prefer'] ?? request.headers['prefer'],
          contains('return=representation'),
        );
        return jsonResponse({
          'code': 'PGRST116',
          'message': 'No rows returned',
        }, 406);
      });
      expect(
        ContentAutomationRepository(client).setSourceEnabled('source-1', false),
        throwsA(isA<PostgrestException>()),
      );
    },
  );

  test(
    'deletion requires a draft row and detects a denied/missing item',
    () async {
      final client = clientFor((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.queryParameters['id'], 'eq.draft-1');
        expect(request.url.queryParameters['status'], 'eq.draft');
        expect(request.url.queryParameters['select'], 'id');
        return jsonResponse({
          'code': 'PGRST116',
          'message': 'No rows returned',
        }, 406);
      });
      expect(
        ContentRepository(client).deleteItem('draft-1'),
        throwsA(isA<PostgrestException>()),
      );
    },
  );

  test('empty topic selection never calls the generation endpoint', () async {
    var requested = false;
    final client = clientFor((_) async {
      requested = true;
      return jsonResponse({}, 200);
    });
    await expectLater(
      ContentAutomationRepository(client).runAutomationNow([]),
      throwsStateError,
    );
    expect(requested, isFalse);
  });
}
