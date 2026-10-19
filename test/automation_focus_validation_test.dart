import 'package:flutter_test/flutter_test.dart';

import 'package:promptwise/data/models/content_automation.dart';
import 'package:promptwise/data/models/learning_topic.dart';

void main() {
  test('enabled automation without selected topic is rejected', () {
    expect(
      () => validateScheduledAutomationFocus(
        enabled: true,
        focusTopics: const [],
      ),
      throwsArgumentError,
    );
  });

  test('enabled with a single selected focus is accepted', () {
    expect(
      () => validateScheduledAutomationFocus(
        enabled: true,
        focusTopics: const [LearningTopic.verification],
      ),
      returnsNormally,
    );
  });

  test('disabled automation may retain empty scheduled focus', () {
    expect(
      () => validateScheduledAutomationFocus(
        enabled: false,
        focusTopics: const [],
      ),
      returnsNormally,
    );
  });

  test('duplicate selections cannot be stored', () {
    expect(
      () => validateScheduledAutomationFocus(
        enabled: true,
        focusTopics: const [LearningTopic.context, LearningTopic.context],
      ),
      throwsArgumentError,
    );
  });
}
