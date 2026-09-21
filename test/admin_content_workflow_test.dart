import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:promptwise/data/models/content_item.dart';
import 'package:promptwise/data/models/content_automation.dart';
import 'package:promptwise/data/models/learning_topic.dart';
import 'package:promptwise/data/repositories/content_repository.dart';
import 'package:promptwise/data/repositories/content_automation_repository.dart';
import 'package:promptwise/presentation/controllers/content_controller.dart';
import 'package:promptwise/presentation/controllers/content_automation_controller.dart';
import 'package:promptwise/presentation/screens/admin/admin_content_management_screen.dart';

const draft = ContentItem(
  id: 'draft-1',
  type: ContentType.lesson,
  title: 'Reviewed AI lesson',
  body: 'Lesson content',
  parentId: 'module-1',
);
const module = ContentItem(
  id: 'module-1',
  type: ContentType.module,
  title: 'Prompting',
  status: ContentStatus.published,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'admin creates, edits, publishes, archives, and deletes draft content',
    () async {
      final repo = _ContentRepository()..rows = [module];
      final content = ContentController(repository: repo);
      addTearDown(content.dispose);
      await content.bindAuthenticatedUser('admin', isAdministrator: true);
      expect(await content.createItem(draft), isTrue);
      expect(content.modules.single.lessons, isEmpty);
      final edited = draft.copyWith(title: 'Edited lesson');
      expect(await content.updateItem(edited), isTrue);
      expect(await content.setStatus(edited, ContentStatus.published), isTrue);
      expect(content.modules.single.lessons.single.title, 'Edited lesson');
      expect(
        await content.deleteItem(
          content.items.firstWhere((item) => item.id == draft.id),
        ),
        isFalse,
      );
      expect(repo.deleted, isEmpty);
      expect(await content.setStatus(edited, ContentStatus.archived), isTrue);
      expect(content.modules.single.lessons, isEmpty);
      expect(await content.setStatus(edited, ContentStatus.draft), isTrue);
      expect(await content.deleteItem(edited), isTrue);
      expect(content.items.map((item) => item.id), ['module-1']);
    },
  );

  test('learners cannot call content mutations', () async {
    final repo = _ContentRepository();
    final content = ContentController(repository: repo);
    addTearDown(content.dispose);
    await content.bindAuthenticatedUser('learner', isAdministrator: false);
    expect(await content.createItem(draft), isFalse);
    expect(await content.updateItem(draft), isFalse);
    expect(await content.deleteItem(draft), isFalse);
    expect(repo.rows, isEmpty);
    expect(repo.deleted, isEmpty);
  });

  test(
    'switching from admin clears drafts and requests published content',
    () async {
      final repo = _ContentRepository()..rows = [module, draft];
      final content = ContentController(repository: repo);
      addTearDown(content.dispose);
      await content.bindAuthenticatedUser('admin', isAdministrator: true);
      await content.bindAuthenticatedUser('learner', isAdministrator: false);
      expect(repo.fetchRoles, [true, false]);
      expect(content.items.map((item) => item.id), ['module-1']);
    },
  );

  test('a pending admin save cannot restore drafts after sign-out', () async {
    final repo = _ContentRepository()..pendingSave = Completer<ContentItem>();
    final content = ContentController(repository: repo);
    addTearDown(content.dispose);
    await content.bindAuthenticatedUser('admin', isAdministrator: true);
    final save = content.createItem(draft);
    await content.bindAuthenticatedUser(null, isAdministrator: false);
    repo.pendingSave!.complete(draft);
    expect(await save, isFalse);
    expect(content.items, isEmpty);
    expect(content.isMutating, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('publishedContentCacheV1'), isNull);
  });

  test(
    'an older refresh cannot overwrite a newly saved content item',
    () async {
      final repo = _ContentRepository();
      final content = ContentController(repository: repo);
      addTearDown(content.dispose);
      await content.bindAuthenticatedUser('admin', isAdministrator: true);
      repo.pendingFetch = Completer<List<ContentItem>>();
      final refresh = content.refresh();
      expect(await content.createItem(draft), isTrue);
      repo.pendingFetch!.complete([]);
      await refresh;
      expect(content.items.single.id, draft.id);
      expect(content.isLoading, isFalse);
    },
  );

  testWidgets('opening Content Management loads newly approved AI content', (
    tester,
  ) async {
    final repo = _ContentRepository();
    final content = ContentController(repository: repo);
    addTearDown(content.dispose);
    await content.bindAuthenticatedUser('admin', isAdministrator: true);
    repo.rows = [draft]; // A Learning Studio approval has created this lesson.
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: content,
        child: const MaterialApp(
          home: Scaffold(body: AdminContentManagementScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(content.items.single.status, ContentStatus.draft);
    await tester.scrollUntilVisible(
      find.text('Reviewed AI lesson'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Reviewed AI lesson'), findsOneWidget);
    expect(content.items.single.status, ContentStatus.draft);
  });

  test(
    'generation keeps partial-run errors while reloading saved drafts',
    () async {
      final repo = _AutomationRepository()
        ..runError = StateError('Partial run: one draft saved.');
      final automation = ContentAutomationController(repository: repo);
      addTearDown(automation.dispose);
      await automation.bindAdministrator(true, userId: 'admin');
      expect(await automation.runNow([LearningTopic.context]), isFalse);
      expect(repo.requestedTopics, [LearningTopic.context]);
      expect(automation.drafts.single.id, 'generated-1');
      expect(automation.errorMessage, contains('Partial run'));
      expect(automation.successMessage, isNull);
      expect(automation.isMutating, isFalse);
    },
  );

  test(
    'admin source controls, settings, generation, and review work',
    () async {
      final repo = _AutomationRepository();
      final automation = ContentAutomationController(repository: repo);
      addTearDown(automation.dispose);
      await automation.bindAdministrator(true, userId: 'admin');
      await automation.refresh();
      expect(await automation.setSourceEnabled('source-1', false), isTrue);
      expect(automation.sources.single.enabled, isFalse);
      expect(
        await automation.saveSettings(
          enabled: true,
          maxArticlesPerRun: 2,
          maxDraftsPerDay: 3,
          monthlyDraftCap: 30,
          maxPendingDrafts: 10,
          maxPendingQuestions: 40,
          draftArchiveDays: 15,
          focusTopics: [LearningTopic.context],
        ),
        isTrue,
      );
      expect(repo.savedTopics, [LearningTopic.context]);
      expect(automation.settings.focusTopics, [LearningTopic.context]);
      expect(await automation.runNow([LearningTopic.verification]), isTrue);
      expect(repo.requestedTopics, [LearningTopic.verification]);
      expect(await automation.publishDraft('generated-1'), isTrue);
      expect(repo.approvedDraft, 'generated-1');
      expect(automation.drafts, isEmpty);
      expect(automation.successMessage, contains('not learner-visible'));
    },
  );

  test(
    'source failure does not optimistically change its enabled state',
    () async {
      final repo = _AutomationRepository()
        ..sourceError = StateError('Permission denied');
      final automation = ContentAutomationController(repository: repo);
      addTearDown(automation.dispose);
      await automation.bindAdministrator(true, userId: 'admin');
      await automation.refresh();
      expect(await automation.setSourceEnabled('source-1', false), isFalse);
      expect(automation.sources.single.enabled, isTrue);
      expect(automation.successMessage, isNull);
    },
  );

  test(
    'changing administrator during a load never leaves the new account stuck',
    () async {
      final repo = _AutomationRepository()
        ..pendingSettings = Completer<AutomationSettings>();
      final automation = ContentAutomationController(repository: repo);
      addTearDown(automation.dispose);
      await automation.bindAdministrator(true, userId: 'admin-a');
      final first = automation.refresh();
      expect(automation.isLoading, isTrue);
      await automation.bindAdministrator(true, userId: 'admin-b');
      expect(automation.isLoading, isFalse);
      final pending = repo.pendingSettings!;
      repo.pendingSettings = null;
      await automation.refresh();
      pending.complete(AutomationSettings.defaults());
      await first;
      expect(automation.hasLoaded, isTrue);
      expect(automation.isLoading, isFalse);
    },
  );

  test('automation requires an identified administrator', () async {
    final repo = _AutomationRepository();
    final automation = ContentAutomationController(repository: repo);
    addTearDown(automation.dispose);
    await automation.bindAdministrator(false, userId: 'learner');
    expect(await automation.runNow([LearningTopic.context]), isFalse);
    expect(await automation.publishDraft('generated-1'), isFalse);
    await automation.bindAdministrator(true);
    expect(await automation.runNow([LearningTopic.context]), isFalse);
    expect(repo.requestedTopics, isNull);
  });
}

class _ContentRepository implements ContentRepository {
  List<ContentItem> rows = [];
  final fetchRoles = <bool>[];
  final deleted = <String>[];
  Completer<ContentItem>? pendingSave;
  Completer<List<ContentItem>>? pendingFetch;
  @override
  Future<List<ContentItem>> fetchItems({
    required bool includeUnpublished,
  }) async {
    fetchRoles.add(includeUnpublished);
    if (pendingFetch != null) return pendingFetch!.future;
    return rows
        .where(
          (item) =>
              includeUnpublished || item.status == ContentStatus.published,
        )
        .toList();
  }

  @override
  Future<ContentItem> createItem(ContentItem item) async {
    if (pendingSave != null) return pendingSave!.future;
    rows.add(item);
    return item;
  }

  @override
  Future<ContentItem> updateItem(ContentItem item) async {
    rows = rows.map((row) => row.id == item.id ? item : row).toList();
    return item;
  }

  @override
  Future<void> deleteItem(String id) async {
    deleted.add(id);
    rows.removeWhere((item) => item.id == id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AutomationRepository implements ContentAutomationRepository {
  Object? runError;
  Object? sourceError;
  List<LearningTopic>? requestedTopics;
  List<LearningTopic>? savedTopics;
  String? approvedDraft;
  Completer<AutomationSettings>? pendingSettings;
  @override
  Future<AutomationSettings> fetchSettings() async => pendingSettings != null
      ? pendingSettings!.future
      : AutomationSettings.defaults();
  @override
  Future<List<LearningContentHealth>> fetchContentHealth() async => [];
  @override
  Future<List<GeneratedContentDraft>> fetchDrafts() async =>
      approvedDraft != null
      ? []
      : [
          GeneratedContentDraft.fromMap({
            'id': 'generated-1',
            'title': 'AI lesson',
            'topic_id': 'context',
            'status': 'draft',
            'draft_payload': {},
          }),
        ];
  @override
  Future<List<QuestionBankReviewItem>> fetchQuestionReviewQueue() async => [];
  @override
  Future<List<QuestionBankReviewItem>> fetchApprovedQuestions() async => [];
  @override
  Future<List<ContentSource>> fetchSources() async => [
    ContentSource.fromMap({
      'id': 'source-1',
      'name': 'Trusted source',
      'enabled': true,
    }),
  ];
  @override
  Future<QueueLifecycleStats> fetchQueueHealth() async =>
      QueueLifecycleStats.empty();
  @override
  Future<String> runAutomationNow(List<LearningTopic> focusTopics) async {
    requestedTopics = focusTopics;
    if (runError != null) throw runError!;
    return 'Draft created for review.';
  }

  @override
  Future<void> setSourceEnabled(String sourceId, bool enabled) async {
    if (sourceError != null) throw sourceError!;
  }

  @override
  Future<void> updateSettings({
    required bool enabled,
    required int maxArticlesPerRun,
    required int maxDraftsPerDay,
    required int monthlyDraftCap,
    required int maxPendingDrafts,
    required int maxPendingQuestions,
    required int draftArchiveDays,
    required List<LearningTopic> focusTopics,
  }) async {
    savedTopics = focusTopics;
  }

  @override
  Future<void> publishDraft(String draftId) async {
    approvedDraft = draftId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
