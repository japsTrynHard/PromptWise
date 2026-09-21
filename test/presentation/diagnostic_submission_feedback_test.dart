import 'package:flutter_test/flutter_test.dart';
import 'package:promptwise/presentation/utils/diagnostic_submission_feedback.dart';

void main() {
  group('diagnosticSubmissionErrorMessage', () {
    test('incomplete answers show a validation message', () {
      expect(
        diagnosticSubmissionErrorMessage(
          ArgumentError('Answer every diagnostic question before submitting.'),
        ),
        'Answer every diagnostic question before submitting.',
      );
    });

    test('already completed does not blame missing answers', () {
      expect(
        diagnosticSubmissionErrorMessage(
          StateError('The diagnostic assessment has already been completed.'),
        ),
        contains('already saved'),
      );
    });

    test('concurrent submission asks user to wait', () {
      expect(
        diagnosticSubmissionErrorMessage(
          StateError('The diagnostic assessment is already being saved.'),
        ),
        contains('still saving'),
      );
    });

    test('unknown state error has a safe fallback', () {
      expect(
        diagnosticSubmissionErrorMessage(StateError('Storage unavailable')),
        contains('Could not save'),
      );
    });

    test('network error does not show the missing-answers message', () {
      final message = diagnosticSubmissionErrorMessage(
        Exception('SocketException: connection timed out'),
      );
      expect(message, contains('Could not save'));
      expect(message, isNot(contains('Answer every')));
      expect(message, isNot(contains('SocketException')));
    });
  });
}
