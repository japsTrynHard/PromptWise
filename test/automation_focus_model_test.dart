import 'package:flutter_test/flutter_test.dart';
import 'package:promptwise/data/models/content_automation.dart';
import 'package:promptwise/data/models/learning_topic.dart';

void main() {
  test('zero cooldown stays disabled even with a future run timestamp', () {
    final now = DateTime.utc(2026, 10, 20);
    final settings = AutomationSettings.fromMap({
      'manual_cooldown_minutes': 0,
      'last_manual_run_at': now
          .add(const Duration(minutes: 1))
          .toIso8601String(),
    });
    expect(settings.manualCooldownMinutes, 0);
    expect(settings.cooldownRemainingAt(now), 0);
  });
  test(
    'learning cooldown applies globally and expires without changing topics',
    () {
      final started = DateTime.utc(2026, 10, 19, 12);
      final settings = AutomationSettings.fromMap({
        'last_manual_run_at': started.toIso8601String(),
        'manual_cooldown_minutes': 30,
        'focus_topics': ['context'],
      });
      expect(settings.cooldownRemainingAt(started), 30);
      expect(
        settings.cooldownRemainingAt(
          started.add(const Duration(minutes: 29, seconds: 30)),
        ),
        1,
      );
      expect(
        settings.cooldownRemainingAt(started.add(const Duration(minutes: 30))),
        0,
      );
      expect(
        settings.cooldownRemainingAt(started.add(const Duration(hours: 1))),
        0,
      );
      expect(AutomationSettings.defaults().cooldownRemainingAt(started), 0);
      expect(settings.focusTopics, [LearningTopic.context]);
    },
  );
  test('an unconfigured schedule has no default focus area', () {
    expect(AutomationSettings.defaults().focusTopics, isEmpty);
    expect(AutomationSettings.fromMap({}).focusTopics, isEmpty);
  });

  test('saved focus areas deserialize using existing learning topic IDs', () {
    final settings = AutomationSettings.fromMap({
      'focus_topics': ['verification', 'context', 'responsible_use'],
    });
    expect(settings.focusTopics, [
      LearningTopic.verification,
      LearningTopic.context,
      LearningTopic.responsibleUse,
    ]);
  });

  test('unknown and repeated IDs do not surface as new selectable topics', () {
    final settings = AutomationSettings.fromMap({
      'focus_topics': ['verification', 'invalid', 'verification'],
    });
    expect(settings.focusTopics, [LearningTopic.verification]);
  });
}
