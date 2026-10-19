// Static structural checks only. These never execute the Flutter app,
// SQL migrations, cloud functions, or the PDF's manual test cases.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source = (path) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const quiz = source('lib/presentation/screens/user/quiz_screen.dart');
const readiness = source('lib/presentation/controllers/image_round_readiness.dart');
const image = source('lib/presentation/screens/user/image_compare_screen.dart');
const imageController = source('lib/presentation/controllers/image_comparison_controller.dart');
const repository = source('lib/data/repositories/content_automation_repository.dart');
const model = source('lib/data/models/content_automation.dart');
const migration = source('supabase/migrations/20260922090000_automation_enabled_requires_focus.sql');
const sqlTest = source('supabase/tests/automation_focus_regression_staging.sql');
let count = 0;
function check(name, fn) { fn(); console.log(`PASS (static): ${name}`); count++; }
check('retry after correct and incorrect outcomes is rendered', () => {
  assert.equal((quiz.match(/label: const Text\('Try Again'\)/g) ?? []).length, 2);
  assert.match(quiz, /if \(!_isCorrect\)/);
});
check('quiz best score ignores incorrect retries', () => {
  assert.match(source('lib/presentation/controllers/progress_controller.dart'), /if \(!isCorrect \|\| !_quizIds\.contains\(quizId\)\) return false;/);
});
check('image readiness requires both decoded frames', () => {
  assert.match(readiness, /_imageA == ImageLoadStatus\.ready &&\s*_imageB == ImageLoadStatus\.ready/);
  assert.match(image, /frameBuilder: \(context, child, frame, wasSyncLoaded\)/);
  assert.match(image, /decodedFrame = frame != null/);
  assert.match(image, /if \(decodedFrame\)/);
});
check('image errors block both choices and provide recovery', () => {
  assert.match(image, /onTap: answered \|\| submitting \|\| !canChoose \? null : onTap/);
  assert.match(image, /onPressed: submitting \|\| !canChoose \? null : onTap/);
  assert.match(image, /onAction: onRetryImages/);
  assert.match(image, /onPressed: onAnotherSet/);
});
check('submission is guarded in screen and controller', () => {
  assert.match(image, /!_imageReadiness\.canSubmit/);
  assert.match(imageController, /required ImageRoundReadiness readiness/);
  assert.match(imageController, /!readiness\.canSubmit/);
  assert.match(imageController, /!_attemptsInFlight\.add\(attemptKey\)/);
});
check('new automation settings rejected before database write', () => {
  assert.match(repository, /validateScheduledAutomationFocus\(\s*enabled:\s*enabled,\s*focusTopics:\s*focusTopics,?\s*\);\s*await _client/);
  assert.match(model, /if \(enabled && focusTopics\.isEmpty\)/);
});
check('migration preserves settings and adds backend check', () => {
  assert.match(migration, /WHERE enabled = true\s+AND cardinality\(focus_topics\) = 0/);
  assert.match(migration, /ALTER COLUMN enabled SET DEFAULT false/);
  assert.match(migration, /CHECK \(NOT enabled OR cardinality\(focus_topics\) BETWEEN 1 AND 5\)/);
});
check('database regression test rolls back mutations', () => {
  assert.match(sqlTest, /BEGIN;/);
  assert.match(sqlTest, /EXCEPTION WHEN check_violation/);
  assert.match(sqlTest, /ROLLBACK;/);
});
console.log(`SUMMARY ${count} static contract checks passed; NOT Flutter or manual QA results.`);
