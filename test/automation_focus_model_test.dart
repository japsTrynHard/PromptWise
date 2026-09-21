import 'package:flutter_test/flutter_test.dart';
import 'package:promptwise/data/models/content_automation.dart';
import 'package:promptwise/data/models/learning_topic.dart';

void main() {
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
