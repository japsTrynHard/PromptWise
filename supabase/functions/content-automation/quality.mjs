// Shared runtime rules: imported by the deployed Edge Function and by Node tests.
const TOPICS = new Set([
  'prompt_clarity', 'context', 'specificity', 'responsible_use', 'verification',
]);
const QUESTION_TYPES = new Set(['concept', 'scenario', 'best_response', 'evaluation']);
const nonEmpty = (value) => typeof value === 'string' && value.trim().length > 0;

export function queueIsFull({ target, pendingDrafts, pendingQuestions,
  pendingVerificationDrafts, maxPendingDrafts, maxPendingQuestions,
  maxPendingVerificationDrafts }) {
  // A full optional Verify queue must never stop core lesson generation.
  return target === 'verification'
    ? pendingVerificationDrafts >= maxPendingVerificationDrafts
    : pendingDrafts >= maxPendingDrafts || pendingQuestions >= maxPendingQuestions;
}

export function classifyRun(draftsCreated, failures) {
  if (!Number.isInteger(draftsCreated) || draftsCreated < 0 ||
      !Number.isInteger(failures) || failures < 0) {
    throw new Error('Invalid automation run counters.');
  }
  if (failures === 0) return 'completed';
  return draftsCreated === 0 ? 'failed' : 'completed_with_errors';
}

export function validateLessonDraft(draft) {
  if (!draft || typeof draft !== 'object' || Array.isArray(draft)) {
    throw new Error('Invalid draft payload.');
  }
  if (!nonEmpty(draft.title) || !nonEmpty(draft.summary)) {
    throw new Error('Generated draft is missing a title or summary.');
  }
  if (!TOPICS.has(draft.topic_id)) throw new Error('Generated topic is invalid.');
  if (!Number.isInteger(draft.target_level) || draft.target_level < 1 || draft.target_level > 5) {
    throw new Error('Generated target level is invalid.');
  }
  if (!Array.isArray(draft.objectives) || draft.objectives.length !== 4) {
    throw new Error('Generated draft must contain exactly four learning objectives.');
  }
  for (const objective of draft.objectives) {
    if (!objective || !nonEmpty(objective.title) || !nonEmpty(objective.description)) {
      throw new Error('Generated learning objective is incomplete.');
    }
  }
  if (!Array.isArray(draft.lesson_sections) || draft.lesson_sections.length !== 6) {
    throw new Error('Generated lesson must contain exactly six sections.');
  }
  for (const section of draft.lesson_sections) {
    if (!nonEmpty(section)) throw new Error('Generated lesson section is empty.');
    const firstBreak = section.indexOf('\n');
    if (firstBreak <= 0 || !nonEmpty(section.slice(0, firstBreak)) ||
        !nonEmpty(section.slice(firstBreak + 1))) {
      throw new Error('Each section must have a heading on its first line and instructional content.');
    }
    const heading = section.slice(0, firstBreak).trim();
    if (heading.split(/\s+/u).length > 16) {
      throw new Error('Generated section heading is too long.');
    }
    const instruction = section.slice(firstBreak + 1).trim();
    const words = instruction.match(/\S+/gu) ?? [];
    if (words.length < 120) {
      throw new Error(`Generated lesson section needs at least 120 instructional words (found ${words.length}).`);
    }
  }
  if (!Array.isArray(draft.questions) || draft.questions.length !== 5) {
    throw new Error('Generated draft must contain exactly five questions.');
  }
  for (const question of draft.questions) {
    if (!question || !QUESTION_TYPES.has(question.question_type)) {
      throw new Error('Generated question type is invalid.');
    }
    if (!nonEmpty(question.stem) || !nonEmpty(question.explanation)) {
      throw new Error('Generated question is incomplete.');
    }
    if (!Array.isArray(question.options) || question.options.length !== 4) {
      throw new Error('Every generated question must have four options.');
    }
    if (!question.options.every(nonEmpty)) {
      throw new Error('Generated question options must be non-empty strings.');
    }
    const normalized = question.options.map((value) => value.trim().toLowerCase());
    if (new Set(normalized).size !== 4) {
      throw new Error('Generated question options must be distinct.');
    }
    if (!Number.isInteger(question.correct_index) || question.correct_index < 0 || question.correct_index > 3) {
      throw new Error('Generated correct answer index is invalid.');
    }
    if (!Number.isInteger(question.difficulty) || question.difficulty < 1 || question.difficulty > 5) {
      throw new Error('Generated question difficulty is invalid.');
    }
  }
  // verification_case is OPTIONAL companion metadata, validated independently
  // AFTER the lesson draft is saved. It cannot invalidate an otherwise good lesson.
}
