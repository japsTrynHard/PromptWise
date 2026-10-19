import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptwise/data/models/learning_survey.dart';
import 'package:promptwise/data/models/learning_topic.dart';
import 'package:promptwise/data/repositories/learning_survey_repository.dart';
import 'package:promptwise/presentation/controllers/learning_survey_controller.dart';

const _valid = LearningSurvey(
  interests: {LearningTopic.verification},
  experienceLevel: 'beginner',
  learningGoal: 'verify_information',
);

class _SurveyFake implements LearningSurveyGateway {
  final rows = <String, LearningSurvey>{};
  bool failFetch = false;
  bool failSave = false;
  Completer<LearningSurvey?>? pending;

  @override
  Future<LearningSurvey?> fetch(String userId) async {
    if (pending != null) return pending!.future;
    if (failFetch) throw StateError('offline');
    return rows[userId];
  }

  @override
  Future<LearningSurvey> save(String userId, LearningSurvey survey) async {
    if (failSave) throw StateError('offline');
    survey.validate();
    rows[userId] = survey;
    return survey;
  }
}

void main() {
  test('TC_SURVEY_NEG_001 a fourth interest cannot be saved', () async {
    final fake = _SurveyFake();
    final c = LearningSurveyController(repository: fake);
    addTearDown(c.dispose);
    await c.bindUser('learner');
    expect(
      await c.submit(
        LearningSurvey(
          interests: LearningTopic.values.take(4).toSet(),
          experienceLevel: 'beginner',
          learningGoal: 'verify_information',
        ),
      ),
      false,
    );
    expect(fake.rows, isEmpty);
  });

  test(
    'TC_SURVEY_POS_003/NEG_003 failed edit preserves saved answers and retries',
    () async {
      final fake = _SurveyFake();
      final c = LearningSurveyController(repository: fake);
      addTearDown(c.dispose);
      await c.bindUser('learner');
      await c.submit(_valid);
      const edited = LearningSurvey(
        interests: {LearningTopic.context, LearningTopic.specificity},
        experienceLevel: 'beginner',
        learningGoal: 'write_better_prompts',
      );
      fake.failSave = true;
      expect(await c.submit(edited), false);
      expect(c.survey, same(_valid));
      expect(fake.rows['learner'], same(_valid));
      fake.failSave = false;
      expect(await c.submit(edited), true);
      await c.retry();
      expect(c.survey!.interests, edited.interests);
      expect(c.errorMessage, isNull);
    },
  );

  test('new learner starts without stored answers', () async {
    final c = LearningSurveyController(repository: _SurveyFake());
    await c.bindUser('new');
    expect(c.isReadyFor('new'), true);
    expect(c.survey, isNull);
    c.dispose();
  });

  test('valid survey saves to account and remains available', () async {
    final fake = _SurveyFake();
    final c = LearningSurveyController(repository: fake);
    await c.bindUser('learner');
    expect(await c.submit(_valid), true);
    expect(fake.rows['learner']?.interests, {LearningTopic.verification});
    expect(c.survey?.learningGoal, 'verify_information');
    c.dispose();
  });

  test('missing interests or invalid goal cannot save', () async {
    final fake = _SurveyFake();
    final c = LearningSurveyController(repository: fake);
    await c.bindUser('learner');
    final invalid = LearningSurvey(
      interests: {},
      experienceLevel: 'beginner',
      learningGoal: 'not_a_goal',
    );
    expect(await c.submit(invalid), false);
    expect(fake.rows, isEmpty);
    expect(c.errorMessage, isNotNull);
    c.dispose();
  });

  test('failed network write cannot show false success', () async {
    final fake = _SurveyFake()..failSave = true;
    final c = LearningSurveyController(repository: fake);
    await c.bindUser('learner');
    expect(await c.submit(_valid), false);
    expect(c.survey, isNull);
    expect(c.errorMessage, contains('Could not save'));
    c.dispose();
  });

  test('switching accounts clears survey and ignores stale fetch', () async {
    final fake = _SurveyFake();
    final pending = Completer<LearningSurvey?>();
    fake.pending = pending;
    final c = LearningSurveyController(repository: fake);
    final old = c.bindUser('account-a');
    fake.pending = null;
    await c.bindUser('account-b');
    pending.complete(_valid);
    await old;
    expect(c.survey, isNull);
    expect(c.isReadyFor('account-b'), true);
    c.dispose();
  });

  test('fetch failure blocks initial form until retry', () async {
    final fake = _SurveyFake()..failFetch = true;
    final c = LearningSurveyController(repository: fake);
    await c.bindUser('learner');
    expect(c.isReadyFor('learner'), false);
    fake.failFetch = false;
    await c.retry();
    expect(c.isReadyFor('learner'), true);
    c.dispose();
  });
}
