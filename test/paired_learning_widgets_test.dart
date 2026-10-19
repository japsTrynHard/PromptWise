import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:promptwise/core/routes/app_routes.dart';
import 'package:promptwise/data/models/content_item.dart';
import 'package:promptwise/data/models/lesson.dart';
import 'package:promptwise/data/models/learning_topic.dart';
import 'package:promptwise/data/models/quiz.dart';
import 'package:promptwise/data/repositories/content_repository.dart';
import 'package:promptwise/presentation/controllers/adaptive_learning_controller.dart';
import 'package:promptwise/presentation/controllers/content_controller.dart';
import 'package:promptwise/presentation/controllers/learning_progression_controller.dart';
import 'package:promptwise/presentation/controllers/progress_controller.dart';
import 'package:promptwise/presentation/screens/user/learn_screen.dart';
import 'package:promptwise/presentation/screens/user/quiz_screen.dart';
import 'package:promptwise/presentation/screens/user/lesson_detail_screen.dart';
import 'package:promptwise/presentation/widgets/module_card.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'TC_LEARN_POS/NEG_001-003 search, module and incomplete filters compose and reset',
    (tester) async {
      _viewport(tester);
      final content = ContentController(repository: _Content());
      final progress = ProgressController(lessonIds: ['a', 'b'], quizIds: []);
      final adaptive = AdaptiveLearningController();
      addTearDown(content.dispose);
      addTearDown(progress.dispose);
      addTearDown(adaptive.dispose);
      await content.bindAuthenticatedUser('learner', isAdministrator: false);
      await progress.init();
      await progress.completeLesson('a');
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: content),
            ChangeNotifierProvider.value(value: progress),
            ChangeNotifierProvider.value(value: adaptive),
          ],
          child: MaterialApp(
            home: const Scaffold(body: LearnScreen()),
            routes: {
              AppRoutes.module: (context) => Scaffold(
                body: Text(
                  (ModalRoute.of(context)!.settings.arguments as Module)
                      .lessons
                      .single
                      .title,
                ),
              ),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ModuleCard), findsNWidgets(2));
      await tester.enterText(
        find.byType(TextField),
        'zz_nonexistent_topic_948',
      );
      await tester.pumpAndSettle();
      expect(find.byType(ModuleCard), findsNothing);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.byType(ModuleCard), findsNWidgets(2));
      await tester.enterText(find.byType(TextField), 'Context');
      await tester.pumpAndSettle();
      expect(
        tester.widget<ModuleCard>(find.byType(ModuleCard)).module.id,
        'module-a',
      );
      expect(progress.progress.completedLessonIds, ['a']);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Module A').last);
      await tester.pumpAndSettle();
      expect(find.byType(ModuleCard), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Verification');
      await tester.pumpAndSettle();
      expect(find.byType(ModuleCard), findsNothing);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ModuleCard>(find.byType(ModuleCard)).module.id,
        'module-a',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All modules').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Incomplete only'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ModuleCard>(find.byType(ModuleCard)).module.id,
        'module-b',
      );
      await tester.tap(find.text('Incomplete only'));
      await tester.pumpAndSettle();
      expect(find.byType(ModuleCard), findsNWidgets(2));
      await tester.enterText(find.byType(TextField), 'Context');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ModuleCard));
      await tester.pumpAndSettle();
      expect(find.text('Context lesson'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'TC_QUIZ_POS_001-003/NEG_001-003 retry waits for the preceding submission',
    (tester) async {
      _viewport(tester);
      final adaptive = _PendingAdaptive();
      final progress = ProgressController(lessonIds: [], quizIds: ['quiz']);
      addTearDown(adaptive.dispose);
      addTearDown(progress.dispose);
      await progress.init();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AdaptiveLearningController>.value(
              value: adaptive,
            ),
            ChangeNotifierProvider.value(value: progress),
          ],
          child: const MaterialApp(
            home: QuizScreen(
              quiz: Quiz(
                id: 'quiz',
                question: 'Which is correct?',
                options: ['Correct choice', 'Wrong choice'],
                correctIndex: 0,
                explanation: 'Compare the answer with the source.',
                topic: LearningTopic.context,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Submit Answer'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Wrong choice'));
      await tester.pump();
      await tester.tap(find.text('Submit Answer'));
      await tester.pump();
      expect(adaptive.calls, 1);
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Try Again'),
            )
            .onPressed,
        isNull,
      );
      adaptive.pending.complete(true);
      await tester.pumpAndSettle();
      expect(progress.bestScoreForQuiz('quiz'), 0);
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Correct choice'));
      await tester.pump();
      adaptive.pending = Completer<bool>();
      await tester.tap(find.text('Submit Answer'));
      await tester.pump();
      adaptive.pending.complete(false);
      await tester.pumpAndSettle();
      expect(adaptive.calls, 2);
      expect(progress.bestScoreForQuiz('quiz'), 100);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'TC_QUIZ_NEG_005 invalid quiz shows unavailable without choices',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: QuizScreen(
            quiz: Quiz(
              id: '',
              question: '',
              options: [],
              correctIndex: 0,
              explanation: '',
            ),
          ),
        ),
      );
      expect(find.text('Quiz unavailable'), findsOneWidget);
      expect(find.text('Submit Answer'), findsNothing);
    },
  );

  testWidgets(
    'TC_LEARN_NEG_004 lesson save failure stays on the lesson with retry feedback',
    (tester) async {
      _viewport(tester);
      final progress = _FailedProgress();
      final progression = LearningProgressionController();
      addTearDown(progress.dispose);
      addTearDown(progression.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProgressController>.value(value: progress),
            ChangeNotifierProvider.value(value: progression),
          ],
          child: MaterialApp(
            home: const LessonDetailScreen(
              lesson: Lesson(
                id: 'a',
                title: 'Context lesson',
                content: 'Provide context for a clear prompt.',
                estimatedMinutes: 2,
                quizId: '',
                topic: LearningTopic.context,
              ),
            ),
            routes: {
              AppRoutes.adaptiveKnowledgeCheck: (_) =>
                  const Scaffold(body: Text('Unexpected navigation')),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Start Knowledge Check'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Start Knowledge Check'));
      await tester.pumpAndSettle();
      expect(find.text('Unexpected navigation'), findsNothing);
      expect(find.textContaining('could not be saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

void _viewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _Content extends ContentRepository {
  _Content()
    : super(
        SupabaseClient(
          'https://example.test',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  @override
  Future<List<ContentItem>> fetchItems({
    required bool includeUnpublished,
  }) async => const [
    ContentItem(
      id: 'module-a',
      type: ContentType.module,
      title: 'Module A',
      status: ContentStatus.published,
    ),
    ContentItem(
      id: 'module-b',
      type: ContentType.module,
      title: 'Module B',
      status: ContentStatus.published,
    ),
    ContentItem(
      id: 'a',
      type: ContentType.lesson,
      parentId: 'module-a',
      title: 'Context lesson',
      body: 'Use context.',
      status: ContentStatus.published,
    ),
    ContentItem(
      id: 'b',
      type: ContentType.lesson,
      parentId: 'module-b',
      title: 'Verification lesson',
      body: 'Check sources.',
      status: ContentStatus.published,
    ),
  ];
}

class _PendingAdaptive extends AdaptiveLearningController {
  Completer<bool> pending = Completer<bool>();
  int calls = 0;
  @override
  Future<bool> recordPracticeAttempt({
    required String itemId,
    required LearningTopic topic,
    required bool isCorrect,
    String attemptType = 'quiz',
    bool countedForMastery = true,
    int? selectedIndex,
  }) {
    calls++;
    return pending.future;
  }
}

class _FailedProgress extends ProgressController {
  _FailedProgress() : super(lessonIds: ['a'], quizIds: []);
  @override
  Future<bool> completeLesson(String lessonId) async => false;
}
