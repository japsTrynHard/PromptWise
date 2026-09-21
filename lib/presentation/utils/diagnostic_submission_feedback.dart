/// Converts a diagnostic submission failure to an actionable, safe message.
/// Do not show raw exception details or falsely say answers are missing for
/// storage, duplicate-submission, or unexpected failures.
String diagnosticSubmissionErrorMessage(Object error) {
  if (error is ArgumentError) {
    return 'Answer every diagnostic question before submitting.';
  }
  if (error is StateError) {
    final detail = error.message.toString().toLowerCase();
    if (detail.contains('already been completed')) {
      return 'Your starting check was already saved. Open your learning path or refresh your progress.';
    }
    if (detail.contains('already being saved')) {
      return 'Your starting check is still saving. Please wait.';
    }
  }
  return 'Could not save your starting check. Please try again. Your selected answers are still on this screen.';
}
