import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptwise/presentation/controllers/progress_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'aggregate legacy quiz score is not assigned to current quiz IDs',
    () async {
      SharedPreferences.setMockInitialValues({'quizScore': 500});
      final controller = ProgressController(
        lessonIds: const ['lesson-1'],
        quizIds: const ['quiz-a', 'quiz-b', 'quiz-c', 'quiz-d', 'quiz-e'],
      );

      await controller.init();

      expect(controller.currentQuizScore, 0);
      expect(controller.progress.quizBestScores, isEmpty);
    },
  );

  test(
    'unowned exact legacy progress is not attached to a signed-in user',
    () async {
      SharedPreferences.setMockInitialValues({
        'quizBestScoresV2': jsonEncode({'quiz-a': 100}),
        'completedLessonIds': <String>['lesson-1'],
      });
      final controller = ProgressController(
        lessonIds: const ['lesson-1'],
        quizIds: const ['quiz-a'],
      );

      await controller.init();
      await controller.bindAuthenticatedUser('user-b');

      expect(controller.bestScoreForQuiz('quiz-a'), 0);
      expect(controller.isLessonCompleted('lesson-1'), isFalse);
    },
  );
}
