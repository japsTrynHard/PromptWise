import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:promptwise/data/models/awareness_article.dart';
import 'package:promptwise/data/models/prompt_coach.dart';
import 'package:promptwise/data/models/user_progress.dart';
import 'package:promptwise/data/repositories/progress_repository.dart';
import 'package:promptwise/data/services/awareness_feed_service.dart';
import 'package:promptwise/data/services/integration_service.dart';
import 'package:promptwise/presentation/controllers/awareness_feed_controller.dart';
import 'package:promptwise/presentation/controllers/progress_controller.dart';
import 'package:promptwise/presentation/controllers/sandbox_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final prompt in ['', '   \n  ', 'Explain.']) {
    test(
      'TC_COACH_NEG_001/002/003 rejects invalid input: ${prompt.length}',
      () async {
        final service = _CoachService();
        final coach = SandboxController(service: service);
        addTearDown(coach.dispose);
        expect(await _review(coach, prompt), isFalse);
        expect(service.calls, 0);
        expect(coach.validationMessage, isNotEmpty);
        expect(coach.analysis, isNull);
      },
    );
  }

  test(
    'TC_COACH_POS_001/003 and NEG_003 revision feedback keeps prior analysis',
    () async {
      final coach = SandboxController(service: null);
      addTearDown(coach.dispose);
      await _review(coach, 'Explain cybersecurity.');
      final original = coach.analysis;
      await _review(coach, 'Explain cybersecurity.');
      expect(coach.scoreImprovement, 0);
      expect(coach.previousAnalysis, same(original));
      expect(coach.revisionNumber, 2);
      await _review(
        coach,
        'Explain cybersecurity for beginners in 3 numbered examples.',
      );
      expect(coach.lastPrompt, contains('beginners'));
      expect(coach.analysis!.suggestions, isNotEmpty);
      expect(coach.previousAnalysis, isNotNull);
    },
  );

  test(
    'TC_COACH_POS_004/NEG_004 clearing invalidates an in-flight AI review',
    () async {
      final service = _CoachService();
      final coach = SandboxController(service: service);
      addTearDown(coach.dispose);
      await coach.bindAuthenticatedUser('learner');
      await coach.checkCoachAvailability();
      coach.setMode(PromptCoachMode.ai);
      final pending = _review(coach, 'Explain cybersecurity for beginners.');
      expect(coach.isLoading, isTrue);
      expect(await _review(coach, 'Explain responsible AI.'), isFalse);
      expect(service.calls, 1);
      coach.startNewSession();
      service.pending.complete(_guidance());
      expect(await pending, isFalse);
      expect(coach.analysis, isNull);
      expect(coach.aiGuidance, isNull);
      expect(coach.lastPrompt, isEmpty);
      expect(coach.revisionNumber, 0);
      expect(await _review(coach, ''), isFalse);
      coach.setMode(PromptCoachMode.standard);
      expect(
        await _review(coach, 'Explain responsible AI for teenagers.'),
        isTrue,
      );
      expect(coach.previousAnalysis, isNull);
      expect(coach.revisionNumber, 1);
    },
  );

  test(
    'TC_COACH_POS_005/NEG_005 unavailable AI is labeled and can be retried',
    () async {
      final service = _CoachService();
      final coach = SandboxController(service: service);
      addTearDown(coach.dispose);
      await coach.bindAuthenticatedUser('learner');
      await coach.checkCoachAvailability();
      coach.setMode(PromptCoachMode.ai);
      final request = _review(
        coach,
        'Write a short AI ethics explainer for teenagers.',
      );
      service.pending.completeError(
        const IntegrationException('network connection failed'),
      );
      await request;
      expect(coach.aiGuidance, isNull);
      expect(coach.serviceMessage, contains('Standard feedback'));
      expect(coach.lastPrompt, contains('AI ethics'));
      expect(coach.isLoading, isFalse);
      service.pending = Completer<PromptAiGuidanceResult>();
      final retry = _review(coach, coach.lastPrompt);
      service.pending.complete(_guidance());
      expect(await retry, isTrue);
      expect(coach.aiGuidance!.summary, 'Verified service feedback');
      expect(coach.serviceMessage, isNull);
    },
  );

  test(
    'TC_LEARN_POS_004/NEG_004 failed cloud save retries without duplicate completion',
    () async {
      final repo = _ProgressRepository();
      final progress = ProgressController(
        lessonIds: ['lesson'],
        quizIds: ['quiz'],
        remoteRepository: repo,
      );
      addTearDown(progress.dispose);
      await progress.init();
      await progress.bindAuthenticatedUser('learner');
      repo.fail = true;
      expect(await progress.completeLesson('lesson'), isFalse);
      expect(progress.syncState, ProgressSyncState.error);
      expect(progress.errorMessage, isNotNull);
      repo.fail = false;
      expect(await progress.completeLesson('lesson'), isTrue);
      expect(progress.syncState, ProgressSyncState.synced);
      expect(progress.errorMessage, isNull);
      expect(repo.saved!.completedLessonIds, ['lesson']);
      final writes = repo.writes;
      expect(await progress.completeLesson('lesson'), isTrue);
      expect(repo.writes, writes);
    },
  );

  test(
    'TC_QUIZ_POS_004/NEG_002/004 best score survives wrong retry and reload',
    () async {
      final progress = ProgressController(lessonIds: [], quizIds: ['quiz']);
      addTearDown(progress.dispose);
      await progress.init();
      expect(
        await progress.recordQuizResult(quizId: 'quiz', isCorrect: false),
        isFalse,
      );
      expect(progress.bestScoreForQuiz('quiz'), 0);
      expect(
        await progress.recordQuizResult(quizId: 'quiz', isCorrect: true),
        isTrue,
      );
      expect(
        await progress.recordQuizResult(quizId: 'quiz', isCorrect: false),
        isFalse,
      );
      expect(progress.bestScoreForQuiz('quiz'), 100);
      final reloaded = ProgressController(lessonIds: [], quizIds: ['quiz']);
      addTearDown(reloaded.dispose);
      await reloaded.init();
      expect(reloaded.bestScoreForQuiz('quiz'), 100);
    },
  );

  test(
    'TC_AWARE_POS_002/NEG_002 latest filter wins over an older pending request',
    () async {
      final service = _FeedService();
      final feed = AwarenessFeedController(service: service);
      addTearDown(feed.dispose);
      final initial = feed.bindAuthenticatedUser('learner');
      final filtered = feed.setCategory(AwarenessCategory.deepfakes);
      expect(service.requests, hasLength(2));
      service.requests[1].complete([_article('deepfake')]);
      await filtered;
      service.requests[0].complete([_article('old')]);
      await initial;
      expect(feed.articles.single.id, 'deepfake');
      final empty = feed.setCategory(AwarenessCategory.privacy);
      service.requests[2].complete([]);
      await empty;
      expect(feed.articles, isEmpty);
      final all = feed.setCategory(null);
      service.requests[3].complete([_article('restored')]);
      await all;
      expect(feed.articles.single.id, 'restored');
      expect(feed.isLoading, isFalse);
    },
  );

  test(
    'TC_AWARE_POS_003/NEG_003 failed updates preserve timestamp and retry loads new content',
    () async {
      final service = _FeedService();
      final feed = AwarenessFeedController(service: service);
      addTearDown(feed.dispose);
      final initial = feed.bindAuthenticatedUser('learner');
      service.requests[0].complete([_article('saved')]);
      await initial;
      final timestamp = feed.lastUpdatedAt;
      service.failCheck = true;
      await feed.checkForUpdates();
      expect(feed.errorMessage, contains('connection'));
      expect(feed.articles.single.id, 'saved');
      expect(feed.lastUpdatedAt, timestamp);
      service.failCheck = false;
      final retry = feed.checkForUpdates();
      await Future<void>.delayed(Duration.zero);
      service.requests[1].complete([_article('new')]);
      await retry;
      expect(feed.errorMessage, isNull);
      expect(feed.articles.single.id, 'new');
      expect(feed.isRefreshing, isFalse);
    },
  );

  test(
    'TC_AWARE_POS_003 manual refresh during loading never leaves the spinner stuck',
    () async {
      final service = _FeedService();
      final feed = AwarenessFeedController(service: service);
      addTearDown(feed.dispose);
      final initial = feed.bindAuthenticatedUser('learner');
      final check = feed.checkForUpdates();
      await Future<void>.delayed(Duration.zero);
      service.requests[1].complete([_article('fresh')]);
      await check;
      service.requests[0].complete([_article('stale')]);
      await initial;
      expect(feed.articles.single.id, 'fresh');
      expect(feed.isLoading, isFalse);
      expect(feed.isRefreshing, isFalse);
    },
  );
}

Future<bool> _review(SandboxController coach, String prompt) =>
    coach.reviewPrompt(prompt, masteryContext: {}, learnerRank: 'Beginner');
PromptAiGuidanceResult _guidance() => PromptAiGuidanceResult(
  guidance: PromptAiGuidance.fromMap({'summary': 'Verified service feedback'}),
  usage: PromptCoachUsage.initial(),
);

class _CoachService extends IntegrationService {
  _CoachService()
    : super(client: SupabaseClient('https://example.test', 'test-key'));
  Completer<PromptAiGuidanceResult> pending =
      Completer<PromptAiGuidanceResult>();
  int calls = 0;
  @override
  Future<PromptCoachServiceStatus> getCoachStatus() async =>
      PromptCoachServiceStatus(
        available: true,
        usage: PromptCoachUsage.initial(),
      );
  @override
  Future<PromptAiGuidanceResult> getPromptGuidance({
    required String prompt,
    required PromptCoachAnalysis standardAnalysis,
    required Map<String, int> masteryContext,
    required String learnerRank,
  }) {
    calls++;
    return pending.future;
  }
}

class _ProgressRepository extends ProgressRepository {
  _ProgressRepository()
    : super(SupabaseClient('https://example.test', 'test-key'));
  bool fail = false;
  int writes = 0;
  UserProgress? saved;
  @override
  Future<UserProgress?> fetchProgress({
    required String userId,
    required int totalLessons,
  }) async => saved;
  @override
  Future<void> upsertProgress({
    required String userId,
    required UserProgress progress,
  }) async {
    writes++;
    if (fail) throw StateError('network unavailable');
    saved = progress;
  }
}

AwarenessArticle _article(String id) => AwarenessArticle.fromMap({
  'id': id,
  'title': 'AI $id',
  'source_url': 'https://example.test/$id',
  'discovered_at': '2026-09-20T00:00:00Z',
});

class _FeedService extends AwarenessFeedService {
  _FeedService()
    : super(client: SupabaseClient('https://example.test', 'test-key'));
  final requests = <Completer<List<AwarenessArticle>>>[];
  bool failCheck = false;
  @override
  Future<List<AwarenessArticle>> fetchFeed({
    AwarenessScope scope = AwarenessScope.forYou,
    AwarenessCategory? category,
    int limit = 80,
    bool refreshIfStale = true,
    bool forceDatabaseRead = false,
  }) {
    final request = Completer<List<AwarenessArticle>>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<String> checkForUpdates() async {
    if (failCheck) throw const AwarenessFeedException('network unavailable');
    return 'Updates loaded';
  }
}
