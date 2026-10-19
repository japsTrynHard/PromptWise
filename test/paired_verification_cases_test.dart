import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:promptwise/data/models/verification.dart';
import 'package:promptwise/data/repositories/verification_repository.dart';
import 'package:promptwise/presentation/controllers/verification_controller.dart';
import 'package:promptwise/presentation/screens/user/verification_session_screen.dart';

void main() {
  test(
    'TC_VERIFY_POS_001-004/NEG_003-004 five answers score once and cannot complete early',
    () async {
      final repo = _Repository();
      final controller = VerificationController(repository: repo);
      await controller.bindAuthenticatedUser('learner');
      expect(await controller.startSession(rankLevel: 1), true);
      expect(controller.session!.cases, hasLength(5));
      expect(await controller.nextCaseOrComplete(), false);
      expect(await controller.completeSession(), false);
      for (var i = 0; i < 5; i++) {
        expect(controller.caseIndex, i);
        final answer = controller.submitCurrentGuess(
          decision: i == 0
              ? VerificationDecision.unsupportedClaim
              : VerificationDecision.supported,
        );
        expect(
          await controller.submitCurrentGuess(
            decision: VerificationDecision.supported,
          ),
          isNull,
        );
        await answer;
        expect(
          await controller.submitCurrentGuess(
            decision: VerificationDecision.supported,
          ),
          isNull,
        );
        expect(controller.feedback, hasLength(i + 1));
        expect(controller.feedback['case-$i']!.decisionCorrect, i != 0);
        if (i < 4) expect(await controller.completeSession(), false);
        expect(await controller.nextCaseOrComplete(), true);
      }
      expect(repo.submissions, 5);
      expect(repo.completions, 1);
      expect(controller.summary!.averageScore, 80);
      expect(controller.summary!.completedCases, 5);
    },
  );

  test(
    'TC_VERIFY_NEG_001 unavailable source gives a recoverable failure',
    () async {
      final controller = VerificationController(
        repository: _Repository()..failStart = true,
      );
      await controller.bindAuthenticatedUser('learner');
      expect(await controller.startSession(rankLevel: 1), false);
      expect(controller.session, isNull);
      expect(controller.errorMessage, isNotEmpty);
      expect(controller.isStarting, false);
    },
  );

  testWidgets(
    'TC_VERIFY_POS_005/NEG_005 Keep going preserves state and Leave works while network stalls',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _Repository();
      final controller = VerificationController(repository: repo);
      await controller.bindAuthenticatedUser('learner');
      await controller.startSession(rankLevel: 1);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const VerificationSessionScreen(),
                    ),
                  ),
                  child: const Text('Open check'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open check'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check my answer'));
      await tester.pump();
      expect(find.text('Pick one answer first.'), findsOneWidget);
      expect(repo.submissions, 0);
      await tester.tap(find.byTooltip('Back to Verify'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();
      expect(find.text('Question 1 of 5'), findsOneWidget);
      expect(controller.hasActiveSession, true);
      await tester.tap(find.byTooltip('Back to Verify'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      expect(find.text('Open check'), findsOneWidget);
      expect(controller.session, isNull);
      expect(controller.summary, isNull);
      expect(repo.completions, 0);
      repo.abandoned.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}

class _Repository extends VerificationRepository {
  _Repository()
    : super(
        SupabaseClient(
          'https://example.test',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  bool failStart = false;
  int submissions = 0;
  int correct = 0;
  int completions = 0;
  final abandoned = Completer<void>();
  @override
  Future<VerificationSession> createSession({
    required int caseCount,
    required int rankLevel,
  }) async {
    if (failStart) throw StateError('network unavailable');
    return VerificationSession.fromMap({
      'session_id': 'session',
      'rank_level': 1,
      'cases': [
        for (var i = 0; i < caseCount; i++)
          {
            'case_id': 'case-$i',
            'title': 'Source check',
            'scenario': 'Compare the claim with the source.',
            'claim_text': 'The source supports this claim.',
            'case_type': 'claim',
            'subskill': 'claim_verification',
            'correct_decision': 'supported',
            'explanation': 'The original source supports this claim.',
            'sequence': i + 1,
          },
      ],
    });
  }

  @override
  Future<VerificationCaseFeedback> submitGuess({
    required String sessionId,
    required String caseId,
    required VerificationDecision decision,
  }) async {
    submissions++;
    final isCorrect = decision == VerificationDecision.supported;
    if (isCorrect) correct++;
    return VerificationCaseFeedback.fromMap({
      'case_id': caseId,
      'subskill': 'claim_verification',
      'correct_decision': 'supported',
      'total_score': isCorrect ? 100 : 0,
      'decision_correct': isCorrect,
      'explanation': 'The original source supports this claim.',
      'learning_point': 'Inspect the source.',
    });
  }

  @override
  Future<VerificationSessionSummary> completeSession(String sessionId) async {
    completions++;
    return VerificationSessionSummary(
      sessionId: sessionId,
      averageScore: correct * 20,
      completedCases: submissions,
      subskillScores: {},
    );
  }

  @override
  Future<void> abandonSession(String sessionId) => abandoned.future;
}
