import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:promptwise/data/models/adaptive_learning.dart';
import 'package:promptwise/data/models/learning_progression.dart';
import 'package:promptwise/data/models/learning_topic.dart';
import 'package:promptwise/data/repositories/learning_progression_repository.dart';
import 'package:promptwise/presentation/controllers/adaptive_learning_controller.dart';
import 'package:promptwise/presentation/controllers/learning_progression_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('TC_ADAPT_POS_001/NEG_001 unmeasured baseline remains unknown', () {
    final controller = AdaptiveLearningController();
    addTearDown(controller.dispose);
    expect(controller.diagnosticCompleted, false);
    expect(controller.overallMastery, 0);
    expect(controller.recommendedTopic, isNull);
    expect(controller.mastery.values.every((m) => m.attempts == 0), true);
  });

  test(
    'TC_SURVEY_POS_004/005 and NEG_004/005 diagnostic validates, scores and persists once',
    () async {
      final controller = AdaptiveLearningController();
      addTearDown(controller.dispose);
      await controller.bindAuthenticatedUser('learner');
      expect(controller.submitDiagnostic({}), throwsArgumentError);
      final answers = {
        for (final q in diagnosticQuestions) q.id: q.correctIndex,
      };
      expect(
        controller.submitDiagnostic({
          ...answers,
          diagnosticQuestions.first.id: -1,
        }),
        throwsArgumentError,
      );
      expect(controller.diagnosticCompleted, false);
      final result = await controller.submitDiagnostic(answers);
      expect(result.correctAnswers, 5);
      expect(result.totalQuestions, 5);
      expect(result.score, 100);
      expect(controller.submitDiagnostic(answers), throwsStateError);
      final reloaded = AdaptiveLearningController();
      addTearDown(reloaded.dispose);
      await reloaded.bindAuthenticatedUser('learner');
      expect(reloaded.diagnosticCompleted, true);
      expect(reloaded.mastery.values.map((m) => m.attempts), everyElement(1));
    },
  );

  test(
    'TC_ADAPT_POS_002/005 and NEG_002 wrong answers reduce measured mastery and progress survives reload',
    () async {
      final controller = AdaptiveLearningController();
      addTearDown(controller.dispose);
      await controller.bindAuthenticatedUser('learner');
      await controller.recordPracticeAttempt(
        itemId: 'right',
        topic: LearningTopic.context,
        isCorrect: true,
      );
      final previous = controller.masteryFor(LearningTopic.context).mastery;
      await controller.recordPracticeAttempt(
        itemId: 'wrong',
        topic: LearningTopic.context,
        isCorrect: false,
      );
      expect(
        controller.masteryFor(LearningTopic.context).mastery,
        lessThan(previous),
      );
      expect(controller.masteryFor(LearningTopic.context).correctAnswers, 1);
      final reloaded = AdaptiveLearningController();
      addTearDown(reloaded.dispose);
      await reloaded.bindAuthenticatedUser('learner');
      expect(reloaded.masteryFor(LearningTopic.context).attempts, 2);
      expect(
        reloaded.masteryFor(LearningTopic.context).mastery,
        controller.masteryFor(LearningTopic.context).mastery,
      );
    },
  );

  test(
    'TC_ADAPT_POS_004/NEG_004 due list respects stored review dates',
    () async {
      final now = DateTime.now();
      SharedPreferences.setMockInitialValues({
        'user:learner:adaptiveMasteryV3': jsonEncode([
          TopicMastery(
            topic: LearningTopic.context,
            mastery: 50,
            attempts: 1,
            correctAnswers: 1,
            nextReviewAt: now.subtract(const Duration(days: 1)),
          ).toMap(),
          TopicMastery(
            topic: LearningTopic.verification,
            mastery: 80,
            attempts: 1,
            correctAnswers: 1,
            nextReviewAt: now.add(const Duration(days: 3)),
          ).toMap(),
        ]),
      });
      final controller = AdaptiveLearningController();
      addTearDown(controller.dispose);
      await controller.bindAuthenticatedUser('learner');
      expect(controller.dueReviews.map((m) => m.topic), [
        LearningTopic.context,
      ]);
    },
  );

  for (final matching in [true, false]) {
    test(
      'TC_LEARN_POS_005/NEG_005 focused practice ${matching ? 'accepts matching' : 'rejects unrelated'} questions',
      () async {
        final repo = _FocusedRepository(matching);
        final controller = LearningProgressionController(repository: repo);
        addTearDown(controller.dispose);
        await controller.bindAuthenticatedUser('learner');
        expect(
          await controller.startAdaptiveSession(
            focusTopic: LearningTopic.context,
            mode: 'focused',
          ),
          matching,
        );
        if (matching) {
          expect(controller.currentQuestion!.topic, LearningTopic.context);
        } else {
          expect(controller.session, isNull);
          expect(
            controller.errorMessage,
            contains('Practice for this lesson topic is unavailable'),
          );
        }
      },
    );
  }
}

class _FocusedRepository extends LearningProgressionRepository {
  final bool matching;
  _FocusedRepository(this.matching)
    : super(SupabaseClient('https://example.test', 'test-key'));
  @override
  Future<KnowledgeCheckSession> createKnowledgeCheck({
    int questionCount = 10,
    LearningTopic? focusTopic,
    String mode = 'adaptive',
  }) async {
    return KnowledgeCheckSession.fromMap({
      'session_id': 'session',
      'mode': mode,
      'focus_topic': focusTopic!.id,
      'questions': [
        for (var i = 0; i < 6; i++)
          {
            'question_id': 'q$i',
            'topic_id': matching
                ? focusTopic.id
                : LearningTopic.verification.id,
            'stem': 'Question $i',
            'options': ['A', 'B'],
            'sequence': i + 1,
          },
      ],
    });
  }
}
