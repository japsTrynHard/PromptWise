import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:promptwise/data/models/learning_topic.dart';
import 'package:promptwise/data/models/verification.dart';
import 'package:promptwise/data/repositories/content_automation_repository.dart';
import 'package:promptwise/data/repositories/content_repository.dart';
import 'package:promptwise/data/repositories/verification_repository.dart';
import 'package:promptwise/presentation/controllers/verification_controller.dart';
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
    'one Learning action finishes all five topics even when only one can be saved per provider window',
    () async {
      final sizes = <int>[];
      var waits = 0;
      final client = clientFor((request) async {
        final topics = List<String>.from(
          jsonDecode(request.body)['focus_topics'],
        );
        sizes.add(topics.length);
        if (topics.length == 1) {
          return jsonResponse({
            'success': true,
            'draftsCreated': 1,
            'message': 'Last draft saved.',
          }, 200);
        }
        return jsonResponse({
          'success': false,
          'retryable': true,
          'partial': true,
          'draftsCreated': 1,
          'pendingTopics': topics.skip(1).toList(),
          'retryAfterSeconds': 1,
          'message': 'One saved; waiting for the provider.',
        }, 202);
      });
      final result = await ContentAutomationRepository(
        client,
        wait: (_) async {
          waits++;
        },
      ).runAutomationNow(LearningTopic.values);
      expect(sizes, [5, 4, 3, 2, 1]);
      expect(waits, 4);
      expect(result, contains('finished after waiting'));
    },
  );

  test(
    'Learning waits and retries only pending selected topics after a partial provider limit',
    () async {
      final requests = <List<dynamic>>[];
      final waits = <Duration>[];
      final progress = <String>[];
      final client = clientFor((request) async {
        requests.add(
          List<dynamic>.from(jsonDecode(request.body)['focus_topics']),
        );
        if (requests.length == 1) {
          return jsonResponse({
            'success': false,
            'retryable': true,
            'partial': true,
            'draftsCreated': 3,
            'pendingTopics': ['responsible_use', 'verification'],
            'retryAfterSeconds': 30,
            'message': '3 drafts saved; provider is busy.',
          }, 202);
        }
        return jsonResponse({
          'success': true,
          'draftsCreated': 2,
          'message': '2 remaining drafts saved.',
        }, 200);
      });
      final result = await ContentAutomationRepository(
        client,
        wait: (duration) async {
          waits.add(duration);
        },
      ).runAutomationNow(LearningTopic.values, onProgress: progress.add);
      expect(requests.first.length, 5);
      expect(requests.last, ['responsible_use', 'verification']);
      expect(waits, [const Duration(seconds: 30)]);
      expect(progress.first, contains('2 remaining'));
      expect(result, contains('finished after waiting'));
    },
  );

  test(
    'Learning automatic continuation is bounded and never claims drafts were saved when none exist',
    () async {
      var calls = 0;
      var waits = 0;
      final client = clientFor((request) async {
        calls++;
        return jsonResponse({
          'success': false,
          'retryable': true,
          'draftsCreated': 0,
          'pendingTopics': ['context'],
          'retryAfterSeconds': 1,
          'error': 'AI provider rate limit.',
        }, 202);
      });
      await expectLater(
        ContentAutomationRepository(
          client,
          wait: (_) async {
            waits++;
          },
        ).runAutomationNow([LearningTopic.context]),
        throwsA(
          isA<StateError>().having(
            (error) => error is PartialGenerationException,
            'must not claim partial saves',
            false,
          ),
        ),
      );
      expect(calls, 3);
      expect(waits, 2);
    },
  );

  test(
    'Learning stops automatic continuation when the administrator session changes',
    () async {
      var current = true;
      var calls = 0;
      final client = clientFor((request) async {
        calls++;
        return jsonResponse({
          'success': false,
          'retryable': true,
          'draftsCreated': 0,
          'pendingTopics': ['context'],
          'retryAfterSeconds': 1,
          'message': 'Provider busy.',
        }, 202);
      });
      await expectLater(
        ContentAutomationRepository(
          client,
          wait: (_) async {
            current = false;
          },
        ).runAutomationNow([
          LearningTopic.context,
        ], shouldContinue: () => current),
        throwsStateError,
      );
      expect(calls, 1);
    },
  );

  test(
    'Learning refuses automatic retries for topics outside the original selection',
    () async {
      var calls = 0;
      final client = clientFor((request) async {
        calls++;
        return jsonResponse({
          'success': false,
          'retryable': true,
          'draftsCreated': 0,
          'pendingTopics': ['verification'],
          'retryAfterSeconds': 1,
          'error': 'Provider busy.',
        }, 202);
      });
      await expectLater(
        ContentAutomationRepository(
          client,
          wait: (_) async {
            fail('must not wait');
          },
        ).runAutomationNow([LearningTopic.context]),
        throwsStateError,
      );
      expect(calls, 1);
    },
  );

  test(
    'existing Learning drafts are a normal availability result with no automatic retry',
    () async {
      final client = clientFor(
        (request) async => jsonResponse({
          'success': true,
          'draftsCreated': 0,
          'existingDraftsAvailable': 1,
          'message': 'Existing lesson draft is ready for review.',
        }, 200),
      );
      expect(
        await ContentAutomationRepository(
          client,
        ).runAutomationNow([LearningTopic.responsibleUse]),
        contains('ready for review'),
      );
      final usedSource = clientFor(
        (request) async => jsonResponse({
          'success': false,
          'noNewContent': true,
          'draftsCreated': 0,
          'message':
              'All matching sources already have approved lessons. No new AI request was charged.',
        }, 200),
      );
      expect(
        await ContentAutomationRepository(
          usedSource,
        ).runAutomationNow([LearningTopic.responsibleUse]),
        contains('already have approved lessons'),
      );
    },
  );

  test(
    'Verify sends unlimited policy and zero cooldown to the settings RPC',
    () async {
      final client = clientFor((request) async {
        expect(
          request.url.path,
          endsWith('/rpc/update_verification_automation_settings'),
        );
        final data = jsonDecode(request.body);
        expect(data['p_unlimited_generation'], true);
        expect(data['p_manual_cooldown_minutes'], 0);
        return jsonResponse({}, 200);
      });
      await VerificationRepository(client).updateAutomationSettings(
        unlimitedGeneration: true,
        enabled: true,
        maxArticlesPerRun: 6,
        maxDraftsPerRun: 2,
        maxDraftsPerDay: 4,
        monthlyDraftCap: 40,
        monthlyGroqRequestCap: 80,
        maxPendingDrafts: 40,
        manualCooldownMinutes: 0,
      );
    },
  );

  test('Verify model preserves unlimited policy and zero cooldown', () {
    final settings = VerificationAutomationOverview.fromMap({
      'settings': {'unlimited_generation': true, 'manual_cooldown_minutes': 0},
      'drafts_today': 10000,
      'remaining_today': null,
    });
    expect(settings.unlimitedGeneration, true);
    expect(settings.manualCooldownMinutes, 0);
    expect(
      VerificationAutomationOverview.defaults().unlimitedGeneration,
      false,
    );
  });

  test(
    'Verify controller reloads server availability when enabling unlimited and restoring limits',
    () async {
      var unlimited = false;
      var cooldown = 15;
      var overviewReads = 0;
      final client = clientFor((request) async {
        if (request.url.path.endsWith(
          '/update_verification_automation_settings',
        )) {
          final data = jsonDecode(request.body);
          unlimited = data['p_unlimited_generation'] == true;
          cooldown = data['p_manual_cooldown_minutes'] as int;
          return jsonResponse({}, 200);
        }
        if (request.url.path.endsWith(
          '/get_verification_automation_overview',
        )) {
          overviewReads++;
          return jsonResponse({
            'settings': {
              'unlimited_generation': unlimited,
              'manual_cooldown_minutes': cooldown,
            },
            'cooldown_remaining_minutes': unlimited ? 0 : cooldown,
          }, 200);
        }
        return jsonResponse([], 200);
      });
      final controller = VerificationStudioController(
        repository: VerificationRepository(client),
      );
      addTearDown(controller.dispose);
      await controller.bindAdministrator(true);
      for (final unlimitedMode in [true, false]) {
        expect(
          await controller.saveAutomationSettings(
            unlimitedGeneration: unlimitedMode,
            enabled: true,
            maxArticlesPerRun: 6,
            maxDraftsPerRun: 2,
            maxDraftsPerDay: 4,
            monthlyDraftCap: 40,
            monthlyGroqRequestCap: 80,
            maxPendingDrafts: 40,
            manualCooldownMinutes: 15,
          ),
          isTrue,
        );
        expect(
          controller.automationOverview.unlimitedGeneration,
          unlimitedMode,
        );
        expect(controller.generationCooldownMinutes, unlimitedMode ? 0 : 15);
      }
      expect(overviewReads, 2);
    },
  );

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
