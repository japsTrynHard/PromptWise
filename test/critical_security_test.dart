import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:promptwise/data/models/learning_topic.dart';
import 'package:promptwise/data/models/verification.dart';
import 'package:promptwise/data/repositories/adaptive_learning_repository.dart';
import 'package:promptwise/data/repositories/content_automation_repository.dart';
import 'package:promptwise/presentation/controllers/content_automation_controller.dart';
import 'package:promptwise/presentation/controllers/verification_controller.dart';
import 'package:promptwise/presentation/screens/admin/admin_verification_studio_screen.dart';
import 'package:promptwise/presentation/widgets/verification_draft_review.dart';

SupabaseClient _client(http.Response Function(http.Request) handler) =>
    SupabaseClient(
      'https://example.invalid',
      'fixture',
      httpClient: MockClient((request) async {
        final response = handler(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
http.Response _json(Object body, int code) => http.Response(
  jsonEncode(body),
  code,
  headers: {'content-type': 'application/json'},
);
final _draft = VerificationCaseDraft.fromMap({
  'id': 'draft-id',
  'title': 'Full draft title',
  'summary': 'Full summary',
  'source_name': 'Credible publisher',
  'source_url': 'https://example.invalid/source',
  'draft_payload': {
    'subskill': 'claim_verification',
    'difficulty': 3,
    'case_type': 'claim',
    'scenario': 'Complete source-grounded scenario',
    'claim_text': 'A precise claim',
    'correct_decision': 'insufficient_evidence',
    'explanation': 'Independent corroboration is missing.',
    'expected_confidence': 'low',
    'learning_point': 'Check independent sources.',
    'source_options': [
      'Original publisher',
      'Unrelated blog',
      'Advert',
      'Forum',
    ],
    'best_source_index': 0,
    'evidence': [
      {
        'code': 'e1',
        'label': 'Original statement',
        'detail': 'Actual available evidence detail',
        'is_key': true,
      },
    ],
    'actions': [
      {
        'code': 'a1',
        'label': 'Read original',
        'description': 'Inspect the complete statement',
        'useful': true,
        'reveals_evidence_codes': ['e1'],
      },
    ],
  },
});

class _Studio extends VerificationStudioController {
  int approvals = 0, rejections = 0;
  @override
  bool get isAdministrator => true;
  @override
  bool get hasLoaded => true;
  @override
  List<VerificationCaseDraft> get drafts => [_draft];
  @override
  Future<void> refresh() async {}
  @override
  Future<bool> approveDraft(String draftId) async {
    approvals++;
    return true;
  }

  @override
  Future<bool> rejectDraft(String draftId) async {
    rejections++;
    return true;
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'secured sessions load without answer/explanation, legacy sessions still load',
    () {
      final item = VerificationCase.fromMap({
        'case_id': 'id',
        'title': 'Question',
        'scenario': 'A claim',
        'subskill': 'claim_verification',
        'answer_hidden': true,
        'decision_options': ['supported', 'unverified'],
      });
      expect(item.isValid, true);
      expect(item.answerHidden, true);
      expect(item.explanation, isEmpty);
      final legacy = VerificationCase.fromMap({
        'case_id': 'id',
        'title': 'Question',
        'scenario': 'A claim',
        'subskill': 'claim_verification',
        'correct_decision': 'supported',
        'explanation': 'Source supports it.',
      });
      expect(legacy.isValid, true);
      expect(legacy.answerHidden, false);
      expect(
        () => VerificationCase.fromMap({'subskill': 'claim_verification'}),
        throwsFormatException,
      );
    },
  );
  test(
    'selected answer goes to new grading RPC; rejected grading never downgrades',
    () async {
      var calls = 0;
      final client = _client((request) {
        calls++;
        expect(request.url.path, endsWith('record_adaptive_answer'));
        expect(jsonDecode(request.body)['p_selected_index'], 2);
        return _json({'code': '22023', 'message': 'Forged correctness'}, 400);
      });
      addTearDown(client.dispose);
      await expectLater(
        AdaptiveLearningRepository(client).recordQuestionAttempt(
          userId: 'user',
          itemId: 'quiz',
          topic: LearningTopic.context,
          isCorrect: true,
          attemptType: 'quiz',
          countedForMastery: true,
          selectedIndex: 2,
        ),
        throwsA(isA<PostgrestException>()),
      );
      expect(calls, 1);
    },
  );
  test('pre-migration backend retains legacy quiz compatibility', () async {
    var calls = 0;
    final client = _client((request) {
      calls++;
      return request.url.path.endsWith('record_adaptive_answer')
          ? _json({
              'code': 'PGRST202',
              'message': 'Could not find the function',
            }, 404)
          : _json(true, 200);
    });
    addTearDown(client.dispose);
    expect(
      await AdaptiveLearningRepository(client).recordQuestionAttempt(
        userId: 'user',
        itemId: 'quiz',
        topic: LearningTopic.context,
        isCorrect: true,
        attemptType: 'quiz',
        countedForMastery: true,
        selectedIndex: 1,
      ),
      true,
    );
    expect(calls, 2);
  });
  test(
    'partial provider 429 is a warning outcome with saved draft count',
    () async {
      final client = _client(
        (_) => _json({
          'partial': true,
          'success': false,
          'verificationDraftsCreated': 4,
          'message': 'Partial verification: HTTP 429',
        }, 200),
      );
      addTearDown(client.dispose);
      await expectLater(
        ContentAutomationRepository(client).runVerificationDraftsNow(
          focusSkills: [VerificationSubskill.claimVerification],
        ),
        throwsA(
          isA<PartialGenerationException>().having(
            (e) => e.message,
            'message',
            contains('4 drafts saved'),
          ),
        ),
      );
    },
  );
  for (final width in [320.0, 1280.0]) {
    testWidgets('full admin review approve reject cancel at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final studio = _Studio(), automation = ContentAutomationController();
      addTearDown(studio.dispose);
      addTearDown(automation.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<VerificationStudioController>.value(
              value: studio,
            ),
            ChangeNotifierProvider.value(value: automation),
          ],
          child: const MaterialApp(
            home: Scaffold(body: AdminVerificationStudioScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Review / approve'));
      expect(find.text('Complete source-grounded scenario'), findsOneWidget);
      expect(
        find.textContaining('Actual available evidence detail'),
        findsOneWidget,
      );
      expect(
        find.text('Independent corroboration is missing.'),
        findsOneWidget,
      );
      expect(find.textContaining('[keyed source]'), findsOneWidget);
      await _tap(tester, find.text('Cancel review'));
      expect(studio.approvals, 0);
      expect(studio.rejections, 0);
      await _tap(tester, find.text('Review / approve'));
      await _tap(tester, find.text('Approve reviewed case'));
      expect(studio.approvals, 1);
      await _tap(tester, find.text('Review / approve'));
      await _tap(tester, find.text('Reject draft'));
      await _tap(tester, find.text('Reject').last);
      expect(studio.rejections, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('missing evidence is shown truthfully in preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VerificationDraftReview(
            draft: VerificationCaseDraft(
              id: 'empty',
              title: 'Old draft',
              summary: 'Summary',
              subskill: VerificationSubskill.claimVerification,
              caseType: VerificationCaseType.claim,
              difficulty: 1,
              sourceName: '',
              sourceUrl: '',
            ),
          ),
        ),
      ),
    );
    expect(find.text('Not supplied in this draft.'), findsWidgets);
    expect(find.text('Open source'), findsNothing);
  });
}
