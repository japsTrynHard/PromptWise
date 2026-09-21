import test from 'node:test';
import assert from 'node:assert/strict';
import {
  FOCUS_TOPICS, validateFocusTopics, resolveFocusTopics, textSupportsFocus,
  selectCandidateFocus, enforceDraftFocus,
} from '../supabase/functions/content-automation/focus.mjs';

const saved = ['context', 'responsible_use'];
const candidate = (title, summary = '') => ({ title, summary, topicHint: 'verification' });

for (const focusTopic of FOCUS_TOPICS) {
  test(`accepts valid focus ${focusTopic}`, () =>
    assert.deepEqual(validateFocusTopics([focusTopic]), [focusTopic]));
}

test('rejects empty, absent, scalar, unknown and duplicate focus selections', () => {
  for (const input of [undefined, null, [], 'verification', ['not_a_topic'],
    ['verification', 'verification'], [null], [1]]) {
    assert.throws(() => validateFocusTopics(input), /Select one or more/);
  }
});

test('accepts all five unique focus areas only', () => {
  assert.deepEqual(validateFocusTopics(FOCUS_TOPICS), FOCUS_TOPICS);
  assert.throws(() => validateFocusTopics([...FOCUS_TOPICS, 'verification']), /Select/);
});

test('scheduled generation uses ONLY saved areas even with a hostile override', () => {
  assert.deepEqual(resolveFocusTopics({ mode: 'scheduled', target: 'all',
    savedTopics: saved, requestedTopics: ['verification'] }), saved);
});

test('schedule with no configured areas pauses instead of defaulting to random', () => {
  assert.deepEqual(resolveFocusTopics({ mode: 'scheduled', target: 'all',
    savedTopics: [], requestedTopics: ['verification'] }), []);
});

test('manual selection is a one-run override and leaves saved array untouched', () => {
  const before = [...saved];
  assert.deepEqual(resolveFocusTopics({ mode: 'manual', target: 'all',
    savedTopics: saved, requestedTopics: ['verification'] }), ['verification']);
  assert.deepEqual(saved, before);
});

test('manual selection cannot silently fall back to saved settings', () => {
  assert.throws(() => resolveFocusTopics({ mode: 'manual', target: 'all',
    savedTopics: saved, requestedTopics: undefined }), /Select/);
});

test('Verify-only automation remains independently configured', () => {
  assert.equal(resolveFocusTopics({ mode: 'manual', target: 'verification',
    savedTopics: [], requestedTopics: undefined }), null);
});

test('focused metadata discovery rejects unrelated, high-scoring AI news', () => {
  assert.equal(selectCandidateFocus(candidate('New ChatGPT model brings general AI updates'), ['verification']), null);
  assert.equal(selectCandidateFocus(candidate('AI misinformation and deepfake verification'), ['verification']), 'verification');
});

test('each curricular area matches its appropriate source vocabulary', () => {
  assert.equal(textSupportsFocus('How to write clear prompts for AI', 'prompt_clarity'), true);
  assert.equal(textSupportsFocus('Adding audience context to AI requests', 'context'), true);
  assert.equal(textSupportsFocus('Set precise output formats for AI prompts', 'specificity'), true);
  assert.equal(textSupportsFocus('AI privacy and protecting personal data', 'responsible_use'), true);
  assert.equal(textSupportsFocus('Fact checking a deepfake image made by AI', 'verification'), true);
  assert.equal(textSupportsFocus('AI privacy considerations', 'verification'), false);
});

test('selected order chooses exactly one appropriate topic per candidate', () => {
  assert.equal(selectCandidateFocus(candidate('Prompt privacy and bias concerns'),
    ['verification', 'responsible_use', 'prompt_clarity']), 'responsible_use');
});

test('draft topic mismatch is rejected even when article matched', () => {
  assert.throws(() => enforceDraftFocus({ topic_id: 'prompt_clarity', title: 'Prompt writing',
    summary: 'Prompt writing.', lesson_sections: ['Prompt writing'] }, 'verification'),
    /does not match/);
});

test('draft with correct topic label but unrelated content is rejected', () => {
  assert.throws(() => enforceDraftFocus({ topic_id: 'verification', title: 'AI market update',
    summary: 'New AI model release.', lesson_sections: ['AI market forecasts'] }, 'verification'),
    /lacks substantive signals/);
});

test('draft with correct topic and source-grounded topical overview and lessons passes', () => {
  assert.doesNotThrow(() => enforceDraftFocus({ topic_id: 'verification',
    title: 'Verify an AI claim', summary: 'Fact checking with sources',
    objectives: [{ title: 'Verification practice', description: 'Check claims' }],
    lesson_sections: ['Verification basics: independently corroborate AI claims.'],
  }, 'verification'));
});

test('draft with relevant overview but unrelated lesson body is rejected', () => {
  assert.throws(() => enforceDraftFocus({ topic_id: 'verification',
    title: 'AI claim verification', summary: 'Fact-checking skills',
    lesson_sections: ['Tips to change your login password'],
  }, 'verification'), /lacks substantive signals/);
});
