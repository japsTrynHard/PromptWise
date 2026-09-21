import test from 'node:test';
import assert from 'node:assert/strict';
import {
  classifyRun, queueIsFull, validateLessonDraft,
} from '../supabase/functions/content-automation/quality.mjs';

const section = (n) => `Section ${n}\n${Array.from({ length: 120 }, (_, i) => `word${i}`).join(' ')}`;
function goodDraft() {
  return {
    title: 'Evidence based prompting', summary: 'Practical source verification',
    topic_id: 'verification', target_level: 3,
    objectives: Array.from({ length: 4 }, (_, i) => ({
      title: `Objective ${i}`, description: 'Apply a useful learning skill.',
    })),
    lesson_sections: Array.from({ length: 6 }, (_, i) => section(i + 1)),
    questions: Array.from({ length: 5 }, (_, i) => ({
      question_type: 'scenario', stem: `How should this be checked ${i}?`,
      explanation: 'Compare evidence and corroborate source.',
      options: ['Source A', 'Source B', 'Source C', 'Source D'],
      correct_index: 0, difficulty: 3,
    })),
    verification_case: null,
  };
}

const rejects = (mutate, error) => {
  const draft = goodDraft();
  mutate(draft);
  assert.throws(() => validateLessonDraft(draft), error);
};

test('accepts a complete lesson draft with 4 objectives, 6 long sections, 5 questions', () => {
  assert.doesNotThrow(() => validateLessonDraft(goodDraft()));
});
test('rejects 3 objectives instead of 4', () => rejects(d => d.objectives.pop(), /exactly four/));
test('rejects extra objectives', () => rejects(d => d.objectives.push(d.objectives[0]), /exactly four/));
test('rejects 5 sections instead of 6', () => rejects(d => d.lesson_sections.pop(), /exactly six/));
test('rejects extra sections', () => rejects(d => d.lesson_sections.push(section(7)), /exactly six/));
test('rejects fewer than 120 instructional words (heading does not count)', () => rejects(d => {
  d.lesson_sections[0] = `Heading\n${Array(119).fill('word').join(' ')}`;
}, /120 instructional words/));
test('rejects missing heading', () => rejects(d => {
  d.lesson_sections[0] = Array(120).fill('word').join(' ');
}, /heading/));
test('rejects section with heading only', () => rejects(d => {
  d.lesson_sections[0] = 'Heading\n';
}, /heading/));
test('rejects 4 questions', () => rejects(d => d.questions.pop(), /exactly five/));
test('rejects extra questions', () => rejects(d => d.questions.push(d.questions[0]), /exactly five/));
test('rejects malformed answer choices safely', () => rejects(d => {
  d.questions[0].options = [null, 'b', 'c', 'd'];
}, /non-empty strings/));
test('rejects duplicate options disregarding case/whitespace', () => rejects(d => {
  d.questions[0].options = ['A', ' a ', 'C', 'D'];
}, /distinct/));
test('rejects out of bounds answer key', () => rejects(d => {
  d.questions[0].correct_index = 4;
}, /index/));
test('rejects bad topic and invalid levels', () => {
  rejects(d => { d.topic_id = 'made_up'; }, /topic/);
  rejects(d => { d.target_level = 6; }, /level/);
});
test('allows optional Verify companion without blocking lesson', () => {
  const draft = goodDraft();
  draft.verification_case = { notYetValidated: true };
  assert.doesNotThrow(() => validateLessonDraft(draft));
});

const queue = {
  target: 'all', pendingDrafts: 3, pendingQuestions: 4,
  pendingVerificationDrafts: 40, maxPendingDrafts: 30,
  maxPendingQuestions: 100, maxPendingVerificationDrafts: 40,
};
test('full optional Verify queue does not stop lesson generation', () => {
  assert.equal(queueIsFull(queue), false);
});
test('Verify target stops at its own cap', () => {
  assert.equal(queueIsFull({ ...queue, target: 'verification' }), true);
});
test('lesson or question queue full still pauses lessons', () => {
  assert.equal(queueIsFull({ ...queue, pendingDrafts: 30 }), true);
  assert.equal(queueIsFull({ ...queue, pendingQuestions: 100 }), true);
});
test('run status identifies normal, failed, and partial executions', () => {
  assert.equal(classifyRun(1, 0), 'completed');
  assert.equal(classifyRun(0, 0), 'completed');
  assert.equal(classifyRun(0, 2), 'failed');
  assert.equal(classifyRun(2, 1), 'completed_with_errors');
});
test('run classification does not accept broken counters', () => {
  assert.throws(() => classifyRun(-1, 0), /Invalid/);
  assert.throws(() => classifyRun(1, NaN), /Invalid/);
});
